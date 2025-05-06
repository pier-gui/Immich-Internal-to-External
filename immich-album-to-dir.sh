#!/bin/bash

# This script moves your phone uploads added to an immich album to an external library directory on your server.
# This solves the ultimate issue that an Immich album is virtual, only exsists in the database.

echo "=== Immich Album Photo Mover Script ==="
# --- CONFIGURATION ---
ALBUM_NAME="2025_Garden"                                    # Monitored album name in immich
SOURCE_DIR="/mnt/user/Photos/library"                       # Host path where immich uploads your phone images
TARGET_DIR="/mnt/user/Photos/Garden/2025"                   # External album target dir path
NEW_CONTAINER_PATH="/libraries/Garden/2025"                 # External album target path inside the container
DRY_RUN=false                                               # For testing without any action set to true
DOCKER_DB_CONTAINER="PostgreSQL_Immich"                     # Your postgres container name  
TEMP_FILE="/mnt/user/immich/immich_kert_assets.csv"         # Temp file location
NEW_LIBRARY_ID="3527ad02-d8b5-4af2-854e-a1d6af79c1db"       # Enter your external library ID from the DB

# Database update settings
NEW_DEVICE_ID="Library Import"                              # Don't change
SET_EXTERNAL=true                                           # Don't change

# Container-to-host path mapping
CONTAINER_PATH_PREFIX="/photos/library"
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
QUERY=$(cat <<EOF
SELECT a.id, a."originalPath"
FROM assets a
JOIN albums_assets_assets aaa ON a.id = aaa."assetsId"
JOIN albums al ON aaa."albumsId" = al.id
WHERE al."albumName" = '$ALBUM_NAME'
AND a."originalPath" LIKE '/photos/library/%';
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
mkdir -p "$TARGET_DIR"

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
    dest_file="$TARGET_DIR/$filename"
    new_db_path="$NEW_CONTAINER_PATH/$filename"
    
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
