#!/bin/sh
dt=`date +'%y%m%d'`
(cd build/Release; zip -r STed2Mac_$dt.zip STed2.app -x \*.DS_Store)
(cd ..; zip -r STed2Mac_src_$dt.zip STed2Mac -x \*.DS_Store -x STed2Mac/build\* -x STed2Mac/\*.zip)
mv ../STed2Mac_src_$dt.zip ./
mv build/Release/STed2Mac_$dt.zip ./
