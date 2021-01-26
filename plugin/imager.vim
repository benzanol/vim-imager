" Imager needs the pixel width and height of the font to position the images,
" so run the function to calculate them if they are not set
let g:imager#enabled = 1
let g:imager#filetypes = ['org', 'note']
let g:imager#all_filetypes = 0
let g:imager#images = {}
let g:imager#max_id = 1
let g:imager#script_path = expand('<sfile>:p:h:h') . '/ueberzug/load-image.sh'

command! EnableImages noa call imager#EnableImages()
command! DisableImages noa call imager#DisableImages()
command! ReloadImages noa call imager#ReloadImages()
command! ToggleImages noa call imager#ToggleImages()

let g:imager#enabled = 0
call imager#EnableImages()

autocmd BufWriteCmd * if g:imager#enabled | call imager#Write() | else | noa write | endif
