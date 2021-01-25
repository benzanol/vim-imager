#!/bin/bash
source "`ueberzug library`"

ImageLayer 0< <(
	ImageLayer::add [identifier]="neovim-$1" [x]="$3" [y]="$4" [max_height]="$5" [path]="$2"
	read
)
