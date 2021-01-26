" Imager needs the pixel width and height of the font to position the images,
" so run the function to calculate them if they are not set
let g:imager#enabled = 0
let g:imager#filetypes = ['org', 'note']
let g:imager#all_filetypes = 0
let g:imager#images = {}
let g:imager#max_id = 1
let g:imager#timer_delay = 10
let g:imager#script_path = expand('<sfile>:p:h:h') . '/ueberzug/load-image.sh'

command! EnableImages noa call s:EnableImages()
command! DisableImages noa call s:DisableImages()
command! ReloadImages noa call s:ReloadImages()
command! ToggleImages noa call s:ToggleImages()

" Remove filler lines when saving
autocmd BufWritePre * if g:imager#enabled | call s:RemoveFillerLines() | endif
autocmd BufWritePost * if g:imager#enabled | call s:AddFillerLines(g:imager#images) | endif
autocmd ExitPre * if g:imager#enabled | call s:DisableImages() | endif

" FUNCTION: s:RenderImages() {{{1
function! s:RenderImages()
	if !g:imager#enabled || !s:IsWindowChanged()
		return 0
	endif

	" Remember the origional window and cursor
	let origional_winid = win_getid()
	let origional_cursor = [line('.'), col('.')]

	" Generate a new list of images
	" Image list dictionary format: {'row,col':{path, height, <terminal>}}
	let new = {}
	let old = g:imager#images

	" Cycle through the windows and call the function to get its images
	let g:bufs = []
	for i in range(1, winnr('$'))
		call win_gotoid(win_getid(i))
		let name_split = split(expand('%:t'), '\.')
		if len(name_split) > 1 && index(g:imager#filetypes, name_split[-1]) > -1
			let window_images = s:GetWindowImages()

			" Add all of the values from the function to the master list
			for q in keys(window_images)
				let new[q] = window_images[q]
			endfor
		endif
	endfor

	" Cycle through old images, and remove all inactive ones
	let any_missing = 0
	for q in keys(old)
		" Migrate the terminal to the new image if there is an identical old one
		if has_key(new, q) && new[q].path == old[q].path && new[q].height == old[q].height
			let new[q].terminal = old[q].terminal

		else
			" Kill the old window if it does not have a new counterpart
			let any_missing = 1
			call s:KillImage(old[q].terminal)
		endif
	endfor

	" Only cycle through new windows if the window list has changed at all
	if any_missing || len(keys(old)) != len(keys(new))
		" Replace all of the filler lines
		call s:RemoveFillerLines()
		call s:AddFillerLines(new)

		" Cycle through the new images, and load all new ones
		for q in keys(new)
			" If the new image hasn't been linked to an old one, render it
			if !has_key(new[q], 'terminal')
				" Get the necessary values for rendering
				let row = split(q, ',')[0] - 1 
				let col = split(q, ',')[1] - 1

				" Set the terminal to the output from showimage
				let new[q].terminal = s:ShowImage(new[q].path, col, row, new[q].height)
			endif
		endfor
	endif

	" Set the global image list to the newly created one
	let g:imager#images = new

	" Return to the origional window and cursor position
	call win_gotoid(origional_winid)
	call cursor(origional_cursor)

	return 1
endfunction
" }}}

" FUNCTION: s:EnableImages() {{{1
function! s:EnableImages()
	let g:imager#enabled = 1

	" Hide the text for defining images
	set concealcursor=nivc
	syntax match imagerDefinition /^.*<< *img path=".\+" height=\d\+ *>>.*$/ conceal
	syntax match imagerDefinition /^.*<< *img height=\d\+ path=".\+" *>>.*$/ conceal
	syntax match imagerFiller /^<<imgline>>$/ conceal

	function! TimerHandler(timer)
		call s:RenderImages()
	endfunction

	let g:tiler#timer = timer_start(g:imager#timer_delay, 'TimerHandler', {'repeat':-1})
endfunction
" }}}
" FUNCTION: s:DisableImages() {{{1
function! s:DisableImages()
	let g:imager#enabled = 0

	" Show the text for defining images
	syntax match imagerDefinition /^.*<< *img path=".\+" height=\d\+ *>>.*$/
	syntax match imagerDefinition /^.*<< *img height=\d\+ path=".\+" *>>.*$/
	syntax match imagerFiller /^<<imgline>>$/ conceal

	" Kill all existing images
	for q in keys(g:imager#images)
		call s:KillImage(g:imager#images[q].terminal)
	endfor

	let g:imager#images = {}
	call s:RemoveFillerLines()
endfunction
" }}}
" FUNCTION: s:ReloadImages() {{{1
function! s:ReloadImages()
	if g:imager#enabled
		call s:DisableImages()
	endif
	call s:EnableImages()
endfunction
" }}}
" FUNCTION: s:ToggleImages() {{{1
function! s:ToggleImages()
	if g:imager#enabled
		call s:DisableImages()
	else
		call s:EnableImages()
	endif
endfunction
" }}}
" FUNCTION: s:Write() {{{1
function! s:Write()
	call s:RemoveFillerLines()
	noa write
	call s:AddFillerLines(g:imager#images)
endfunction
" }}}

" FUNCTION: s:IsWindowChanged() {{{1
" Detect if there are changes to the current window
function! s:IsWindowChanged()
	" Check if the cursor has moved or the file has changed
	let properties = [{'name':'winid', 'command':'win_getid()'},
				\ {'name':'file', 'command':'expand("%:p")'},
				\ {'name':'window_position', 'command':'win_screenpos(winnr())'},
				\ {'name':'window_size', 'command':'winwidth(0) . "," . winheight(0)'},
				\ {'name':'window_lines', 'command':'line("w0") . "," . line("w$")'},
				\ {'name':'line_rows', 'command':'screenpos(0, line("w0"), 1).row . "," . screenpos(0, line("w$"), 1).row'},
				\ {'name':'cursor', 'command':'line(".") . "," . col(".")'},
				\ {'name':'getline', 'command':'getline(".")'},
				\ {'name':'maxline', 'command':'line("$")'}]

	" Create a new list of properties
	if exists('g:imager#properties')
		let old =  g:imager#properties
	else
		let old = {}
	endif

	let new = {}
	let changed = 0
	for q in properties
		execute 'let new[q.name] = string(' . q.command . ')'
		if !has_key(old, q.name) || new[q.name] != old[q.name]
			let changed = 1
		endif
	endfor
	let g:imager#properties = new

	return changed
endfunction
" }}}
" FUNCTION: s:GetWindowImages() {{{1
function! s:GetWindowImages()
	call add(g:bufs, bufnr())
	" Create a list
	let image_dict = {}

	" Search the displayed lines
	let first_line = max([1, line('w0')])
	let last_line = line('w$')
	for i in range(first_line, last_line)
		let line = getline(i)

		" Check if the line matches one of the valid image formats
		if foldclosed(i) <= 0 && line != '' &&
					\ ( substitute(line, '^.*<< *img path=".\+" height=\d\+ *>>.*$', '', 'i') == '' ||
					\   substitute(line, '^.*<< *img height=\d\+ path=".\+" *>>.*$', '', 'i') == '' )

			let new_image = {}

			" Parse the data from the line, and add it to the window image list
			let new_image.height = str2nr(substitute(line, '^.*height=\(\d\+\).*$', '\1', 'i'))
			let new_image.path = substitute(line, '^.*path="\(.\+\)".*$', '\1', 'i')

			let parents = 0
			for q in split(new_image.path, '\zs')
				if q == '.'
					let parents += 1
					continue
				endif
				break
			endfor

			if parents > 0
				let new_image.path = expand('%:p' . repeat(':h', parents)) . new_image.path[parents:-1] 
			endif

			" Add the buffer and line to the data
			let new_image.buffer = bufnr()
			let new_image.line = i

			" Get the screen coords of the image to use as the key
			let image_index = len(substitute(line, '<<img .*', '', 'i')) + 1
			let g:img = image_index
			let coords = screenpos(0, i, image_index)
			let coord_string = coords.row . ',' . (coords.col - 1)
			let image_dict[coord_string] = new_image
		endif
	endfor

	return image_dict
endfunction
" }}}
" FUNCTION: s:ShowImage(x, y, dict) {{{1
" Display a single image at a certain terminal position
function! s:ShowImage(path, x, y, height)
	let origional_winid = win_getid()

	" Format the command to execute
	let identifier = getpid() . '-' . g:imager#max_id
	let g:imager#max_id += 1

	let command = printf('%s %s %s %s %s %s', g:imager#script_path, identifier, a:path, a:x, a:y, a:height)
	let g:cmd = command

	" Run the command in a terminal in a new tab, then close it
	new
	call termopen(command)
	setlocal nobuflisted
	let terminal_buffer = bufnr()
	close!

	" Return to the origional buffer
	call win_gotoid(origional_winid)

	return terminal_buffer
endfunction
" }}}
" FUNCTION: s:KillImage(terminal) {{{1
function! s:KillImage(terminal)
	execute a:terminal . 'bdelete!'
endfunction
" }}}
" FUNCTION: s:RemoveFillerLines() {{{1
function! s:RemoveFillerLines()
	silent! windo %s/<<imgline>>\n//
endfunction
" }}}
" FUNCTION: s:AddFillerLines(images) {{{1
function! s:AddFillerLines(images)
	let origional_buffer = bufnr()

	for q in keys(a:images)
		" Open the buffer and add the lines
		execute a:images[q].buffer . 'buffer'
		call append(a:images[q].line, repeat(['<<imgline>>'], a:images[q].height - 1))
	endfor

	" Return to the origional buffer
	execute origional_buffer . 'buffer'
endfunction
" }}}

" Enable on startup
call s:EnableImages()
