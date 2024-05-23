#!/bin/bash

# Version 1.1.4
# The program initializes files sequentially.
# Each file is initialized by one provider.
# When the provider finishes initializing the file, it is given the next one.
# In this way, all providers will be used until there are no files left in the initialization queue.
# Even if the providers are different in power, this will not lead to downtime for the more powerful ones.
# Initialization will continue from where it was interrupted

# Get postcli: https://github.com/spacemeshos/post/releases
# RTM https://github.com/spacemeshos/post/blob/develop/cmd/postcli/README.md
#
# Based on Samovar's (PlainLazy) Powershell script
# https://github.com/PlainLazy/crypto
# Thank you!

# edit this section
providers=(0 1 2 3 4 5 6 7)  # in this case GPU0 and GPU1 are used (also you can use CPU, its number is 4294967295)
atx="00963908775736dc36c314b9c25eb87b3b274d43310a7a8febaf6b7914cd022d"  # Use latest Highest ATX (Hex)
nodeId="4906880e4f2d36c2400a91250fde767e946130900585a9c4e169d25ca2fed0be"  # Your public nodeId (smehserId)
fileSize=$((64 * 1024 * 1024 * 1024))  # 64 GiB  (For larger volumes, for convenience, you can increase to 4,8,16+ GiB)
numUnits=87  # 64 GiB each (mininum 4)

# If you want to manually set the scope of work you can set this following variables
startFromFile=44	# The file number the script starts from
finishAtFile=0	# The last file that will be created. Calculated from "numUnits" if set to 0

dataDir="/home/user/post"
postcli="./postcli"
# end edit section

if [[ $finishAtFile -gt 0 ]]; then
filesToDo=$(($finishAtFile +1))
filesTotal=$(($filesToDo - $startFromFile))
else
filesToDo=$(($numUnits * 64 * 1024 * 1024 * 1024 / $fileSize))
filesTotal=$filesToDo
fi
echo "Total files $filesTotal"
declare -A processes
declare -a filesArray
fileCounter=$startFromFile
mainLoop=true
expectedFileNum=0
providerCounter=0
providersLength=${#providers[@]}

# Creating an array of existing or missing files
while IFS= read -r line; do
    dirName=$(dirname "$line")
    
    fileName=$(basename "$line")
    fileNum=${fileName#*_}
    fileNum=${fileNum%.*}
    
    filesArray+=("$dirName:$fileNum")
done < <(find "$dataDir" -maxdepth 1 -type f -name 'postdata_*.bin')

IFS=$'\n' filesArray=($(sort -t ":" -k2n <<<"${filesArray[*]}"))
unset IFS

for i in "${!filesArray[@]}"; do
    currentFileNum=${filesArray[$i]#*:}

    while (( currentFileNum != expectedFileNum )); do
        currentProvider=${providers[$providerCounter]}
        filesArray+=("$dataDir:$expectedFileNum")
        ((providerCounter=(providerCounter+1)%providersLength))
        ((expectedFileNum++))
    done

    ((expectedFileNum++))
done

IFS=$'\n' filesArray=($(sort -t ":" -k2n <<<"${filesArray[*]}"))
unset IFS

# Checking of already created files, continue initialization if unfinished
amt=${#filesArray[@]}
if [[ $amt -gt 0 ]]; then
	while ((fileCounter < amt)); do
		for p in "${providers[@]}"; do
			postFile=${filesArray[fileCounter]}
			oldIFS=$IFS
	    	IFS=":"
	    	read -ra pFile <<< "$postFile"
	    	IFS=$oldIFS

	    	if [ -z "${processes[$p]}" ] || ! kill -0 ${processes[$p]} 2> /dev/null; then
		    	echo "Checking existing file: $dataDir/postdata_$fileCounter.bin"
		    	echo "-----------------------------------------------------------------"
		    	nice -n 19 $postcli -provider $p -commitmentAtxId $atx -id $nodeId -labelsPerUnit 4294967296 -maxFileSize $fileSize -numUnits $numUnits -datadir $dataDir -fromFile $fileCounter -toFile $fileCounter & processes[$p]=$!
		    	((fileCounter++))
		    	if [[ "$fileCounter" -eq "$filesToDo" ]]; then
		        	mainLoop=false
		        	break 2
		    	fi
		    	if [[ "$fileCounter" -eq "$amt" ]] ; then # additional check in case if the number of providers changed
		        	break
		    	fi
	    	fi
    	done
    	sleep 0.2
	done
fi

# All previously created files have been done, we continue with the normal procedure
if $mainLoop; then
	while (( fileCounter < filesToDo )); do
    	for p in "${providers[@]}"; do
            if [ -z "${processes[$p]}" ] || ! kill -0 ${processes[$p]} 2> /dev/null; then
                echo " Provider $p starts processing a new file: $dataDir/postdata_$fileCounter.bin (Total files:$filesTotal)"
                echo "-----------------------------------------------------------------"
                nice -n 19 $postcli -provider $p -commitmentAtxId $atx -id $nodeId -labelsPerUnit 4294967296 -maxFileSize $fileSize -numUnits $numUnits -datadir $dataDir -fromFile $fileCounter -toFile $fileCounter & processes[$p]=$!
                ((fileCounter++))
            fi
    	done
    	sleep 1
	done
fi

echo "Almost there"
echo "Waiting for background processes to finish"
echo "------------------------------------------"
wait
echo "All done!"
read -p "Press enter to continue"
read -p "Press enter to continue"
