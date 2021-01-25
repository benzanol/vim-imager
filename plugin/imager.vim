" Imager needs the pixel width and height of the font to position the images,
" so run the function to calculate them if they are not set
let g:imager#filetypes = ['org', 'note']
let g:imager#images = {}
let g:imager#max_id = 1
let g:imager#script_path = expand('<sfile>:p:h:h') . '/ueberzug/load-image.sh'

let g:imager#enabled = 0
call imager#EnableImages()
