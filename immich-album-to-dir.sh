#!/bin/bash

# Modifided from original script at https://github.com/dansity/Immich-Album-to-Directory
# This script moves photos from the immich internal library to an external library.
# My use case was to move already-uploaded assets to the Synology Photos folder. Future uploads are from SP but I wanted to keep albums made in immich (and access future SP uploads in immich).
# The external library will store photos in the same folder structure as the immich internal library. Update the storage template and run the Storage Template Migration Job in immich first.
#	To match Synology Photos, the template would be {{y}}/{{MM}}/{{filename}}

echo "=== Immich Photo Mover Script ==="
# --- CONFIGURATION ---
ALBUM_NAME="Test"                                    		# Add the photos to this album in immich. All photos in this immich album will be moved
SOURCE_DIR="/volume1/docker/immich-app/library/library"   	# Host path to immich uploads (note, I didn't include the folder with the immich user name)
TARGET_DIR="/volume1/photo"                   				# Path for External Library files (and folder structure)
NEW_CONTAINER_PATH="/volume1/photo"                 		# External album target path inside the container (often set as the same path as TARGET_DIR)
DRY_RUN=true                                              	# For testing without any action set to true
DOCKER_DB_CONTAINER="immich_postgres"                     	# Your postgres container name  
TEMP_FILE="/volume1/photo/immich_kert_assets.csv"         	# Temp file location
NEW_LIBRARY_ID="68216611-9b60-416c-abe5-e40525776587"       # Enter your external library ID from the DB. I found this with "sudo docker logs immich_server". The line contained "GET /api/libraries/" then the ID.

# Database update settings
NEW_DEVICE_ID="Library Import"                              # Don't change
SET_EXTERNAL=true                                           # Don't change

# Container-to-host path mapping
	# Find the values below within the immich Folder Explorer
CONTAINER_PATH_PREFIX="upload/library"						# Within the container, the Internal library path before the user name
ORIGINAL_PATH_TRIM="upload/library/admin"					# Within the container, the Internal library path up to (including) the user name
HOST_PATH_PREFIX="$SOURCE_DIR"
# --- BEGIN SCRIPT ---
echo "[CONFIG] Album: $ALBUM_NAME"
echo "[CONFIG] Source Dir: $SOURCE_DIR"
echo "[CONFIG] Target Dir: $TARGET_DIR"
echo "[CONFIG] Dry Run Mode: $DRY_RUN"
echo "[CONFIG] New DB Path: $NEW_CONTAINER_PATH"
echo "[CONFIG] Docker DB Name: $DOCKER_DB_CONTAINER"
echo "[CONFIG] Temp File: $TEMP_FILE"
echo "[CONFIG] New Device ID: $NEW_DEVICE_ID"
echo "[CONFIG] New Library ID: $NEW_LIBRARY_ID"
echo "[CONFIG] Set External: $SET_EXTERNAL"

mkdir -p "$(dirname "$TEMP_FILE")"
rm -f "$TEMP_FILE"
touch "$TEMP_FILE"
echo "[INFO] Executing query to find matching assets in album '$ALBUM_NAME'..."
# Edit the LIKE instruction to match the first part of the container path to the internal library (% is a wildcard). This ensures that only internal assets will get moved.
QUERY=$(cat <<EOF
SELECT a.id, a."originalPath"
FROM assets a
JOIN albums_assets_assets aaa ON a.id = aaa."assetsId"
JOIN albums al ON aaa."albumsId" = al.id
WHERE al."albumName" = '$ALBUM_NAME'
AND a."originalPath" LIKE 'upload/library/admin/%';
EOF
)
docker exec -i "$DOCKER_DB_CONTAINER" psql -U postgres -d immich -t -A -F ',' -c "$QUERY" > "$TEMP_FILE"
ASSET_COUNT=$(wc -l < "$TEMP_FILE")
if [[ "$ASSET_COUNT" -eq 0 ]]; then
    echo "[WARNING] No matching assets found!"
    cat "$TEMP_FILE"
    exit 0
fi
echo "[INFO] Found $ASSET_COUNT matching image(s)."
echo "[INFO] Starting file operations..."

# Process counter
processed=0

# Process the entire file by reading it line by line
mapfile -t csv_lines < "$TEMP_FILE"
for line in "${csv_lines[@]}"; do
    # Parse the line
    asset_id=$(echo "$line" | cut -d',' -f1)
    original_path=$(echo "$line" | cut -d',' -f2)
    
    # Skip empty lines
    [[ -z "$asset_id" || -z "$original_path" ]] && continue
    
    # Map container path to host path
    src_file="${original_path/$CONTAINER_PATH_PREFIX/$HOST_PATH_PREFIX}"
	filename=$(basename "$src_file")
	dest_file="${original_path/$ORIGINAL_PATH_TRIM/$TARGET_DIR}"
	new_db_path="${original_path/$ORIGINAL_PATH_TRIM/$NEW_CONTAINER_PATH}"
    
    echo "[CHECK] Asset ID: $asset_id"
    echo "[CHECK] Container path: $original_path"
    echo "[CHECK] Host path: $src_file"
    
    if [[ ! -f "$src_file" ]]; then
        echo "[SKIP] File not found: $src_file"
        continue
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would move: '$src_file' -> '$dest_file'"
        echo "[DRY RUN] Would update DB: asset $asset_id originalPath = '$new_db_path'"
        echo "[DRY RUN] Would update deviceId = '$NEW_DEVICE_ID'"
        echo "[DRY RUN] Would update libraryId = '$NEW_LIBRARY_ID'"
        echo "[DRY RUN] Would update isExternal = $SET_EXTERNAL"
    else
        echo "[ACTION] Moving file to: $dest_file"
		
		#create new path first if it doesn't exist in the external library
		new_path="${dest_file/$filename}"
		mkdir -p "$new_path"
		
		mv "$src_file" "$dest_file"
        mv_status=$?
        
        if [[ $mv_status -eq 0 ]]; then
            echo "[ACTION] Updating database for asset $asset_id..."
            
            # Construct the full SQL update query with all fields
            DB_UPDATE_QUERY="UPDATE assets SET 
                \"originalPath\" = '$new_db_path',
                \"deviceId\" = '$NEW_DEVICE_ID',
                \"libraryId\" = '$NEW_LIBRARY_ID',
                \"isExternal\" = $SET_EXTERNAL
                WHERE id = '$asset_id';"
            
            # Execute the database update
            docker exec -i "$DOCKER_DB_CONTAINER" psql -U postgres -d immich -c "$DB_UPDATE_QUERY"
            db_status=$?
            
            if [[ $db_status -eq 0 ]]; then
                processed=$((processed+1))
                echo "[SUCCESS] Processed asset $asset_id ($processed/$ASSET_COUNT)"
            else
                echo "[ERROR] Database update failed for asset $asset_id"
            fi
        else
            echo "[ERROR] File move failed for $src_file"
        fi
    fi
done

echo "[INFO] Successfully processed $processed out of $ASSET_COUNT assets."
echo "[CLEANUP] Removing temp file..."
rm -f "$TEMP_FILE"
echo "[DONE] All done."

