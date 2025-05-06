# Immich Album to a local directory

## What does this script solves?

Probably similar to others I'm adding images to my immich in two ways:
1. I'm uploading curated images to my NAS from my DSLR camera into dated folders
2. Using immich auto backup feature to upload photos to immich

What is the issue then?

The mobile uploads are dumped in a "bucket" by immich and no album directories are created on my NAS after photos added to albums.
The storage template does not solve this, that is just a directory structure for the fresh uploaded files.

## Why the existing immich albums are not enough?
The database immich creates cannot be read by other software. For example if I want to check some photos on Plex on my TV I don't have albums.

## What the script does?
It checks if a mobile upload is part of an existing album and moves it to a similarly named directory to your external library.
The script modifies the database so immich thinks the photo was already uploaded as an external library file.
Since immich skips existing photos from upload it will not be uploaded again from your phone.

# Disclaimer
This script modifies the database. Create database backup! To dial it in I suggest try it with a single image on one album. If it worked you can
extend it to multiple images.

## Known limitations
This script can only deal with a single album. So if you have multiple albums you need to create copies of the script.

# How to use?

## Prerequisites:
1. Immich is running in a docker container
2. Postgres is running in a docker container
3. Your NAS is a linux based system that can execute cron jobs

Add the script to crontab (User Scripts in Unraid) and change the variables in the beginning of the script.

Tested and using it on Unraid 7
