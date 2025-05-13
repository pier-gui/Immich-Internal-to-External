# Immich Internal library assets to external library

This script will move assets within immich's internal library to an external library. The internal folder structure is copied to the external library.

My reason for this: I started with immich to manage photo/video uploads to my Synology NAS, but needed to move away from that because of poor iOS app performance.
I already had a large asset library in immich and didn't want to lose the many albums I had created in immich. And I still wanted the option of using immich as a front-end.

Essentially this helped me achieve the following setup, from my starting point in which I only had assets in the internal immich library
- Synology Photos is used to backup photos from iOS and Android phones. SP stores the assets within year and month folders on the NAS shared photos folder.
- immich has access to the shared photos folder as an external library.
- As long as I don't move assets or change the shared folder structure, assets will be in their expected locations for both immich and SP

# Setup
I have a Synology NAS with DSM 7. Immich (v1.132.3) is running in a Docker container on the NAS.

# How does it work?
The script will find all assets within an immich album that are stored in the Internal library, and move them to the specified external library.
The internal library folder structure is retained in the external library location.
The immich database is updated to recognized the asset in its new storage location, and retains all other immich data (albums, machine learning, thumbnails...).

# Warning
I'm offering this up without any guarantees. All I can say is that it worked on my system.
I don't know what would happen if the script tried to move an asset but a file with the same name already exists in the destination folder, for example.

# How to use it?
1. Set your immich internal library storage template as you want the external library to be organized, and run the storage template migration job.
  I set mine to match how Synology Photos stores photos: {{y}}/{{MM}}/{{filename}}
2. Create an album in immich with a few assets that you want to move (I suggest doing only a few or a single asset initially to make sure it works)
3. Set the script variables to match your setup. See comments in the script for guidance.
4. Run the script (works with DSM Task Scheduler but SSH is better since you can see what's happening)
5. Add more assets to the immich album and repeat
