
sudo rm  '/media/crclayton/charlietv/.Trash-1000' -rf
sudo rm  '/media/crclayton/TOSHIBA EXT/.Trash-1000' -rf
sudo rm  '/mnt/usb-Seagate_Portable_NT36HR1Y-0:0-part1/.Trash-1000' -rf

cd  '/media/crclayton/charlietv/'
detox . -r -v

cd  '/media/crclayton/TOSHIBA EXT/'
detox . -r -v

cd '/mnt/usb-Seagate_Portable_NT36HR1Y-0:0-part1/'
detox . -r -v

#rsync -hvrltD --progress --size-only --ignore-existing '/media/crclayton/TOSHIBA EXT' '/media/crclayton/Seagate Portable Drive'
#rsync -hvrPt --delete --ignore-existing '/media/crclayton/TOSHIBA EXT' '/media/crclayton/Seagate Portable Drive'
#rsync -hvrPt --ignore-existing '/media/crclayton/TOSHIBA EXT' '/mnt/usb-Seagate_Portable_NT36HR1Y-0:0-part1' #/media/crclayton/Seagate Portable Drive'


# put TOSHIBA onto master charlietv
rsync -hvrPt --ignore-existing '/media/crclayton/TOSHIBA EXT/TV' '/media/crclayton/charlietv'
rsync -hvrPt --ignore-existing '/media/crclayton/TOSHIBA EXT/New' '/media/crclayton/charlietv'

# put charlietv TV onto TOSHIBA
rsync -hvrPt --ignore-existing '/media/crclayton/charlietv/TV' '/media/crclayton/TOSHIBA EXT'

# put charlietv Movies onto Seagate
rsync -hvrPt --ignore-existing '/media/crclayton/charlietv/Movies' '/mnt/usb-Seagate_Portable_NT36HR1Y-0:0-part1'

