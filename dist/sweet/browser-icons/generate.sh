#!/bin/bash

for b in "brave" "chromium" "google-chrome" ; do
mkdir $b
for i in 16 24 32 48 64 128 256; do
  f=$b/product_logo_${i}.png
  echo $f
  magick -background none -density 300 $b.svg -resize ${i}x${i} $f

done
done
