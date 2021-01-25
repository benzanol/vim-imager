" Imager needs the pixel width and height of the font to position the images,
" so run the function to calculate them if they are not set
let g:imager#filetypes = ['org']
let g:imager#terminals = []
let g:imager#windows = {}

command! TestImage call imager#display#ShowImage('~/Pictures/Wallpaper/MountainWallpaper.jpg', 1, 3, 2)
autocmd CursorMoved *.org call imager#RenderImages()

syntax match imageDefinition /.*!img path:".\+" height:\d\+$/ conceal
