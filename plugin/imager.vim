" Imager needs the pixel width and height of the font to position the images,
" so run the function to calculate them if they are not set
let g:imager#enabled = 0
let g:imager#used_latex = 0
let g:imager#filetypes = ['org', 'note']
let g:imager#all_filetypes = 0
let g:imager#images = {}
let g:imager#max_id = 1
let g:imager#timer_delay = 10
let g:imager#ueberzug_path = expand('<sfile>:p:h:h') . '/ueberzug/load-image.sh'

command! EnableImages noa call s:EnableImages()
command! DisableImages noa call s:DisableImages()
command! ReloadImages noa call s:ReloadImages()
command! ToggleImages noa call s:ToggleImages()
command! RefreshImages noa call s:RenderImages()

" Remove filler lines when saving
autocmd BufWritePre * if g:imager#enabled | call s:RemoveFillerLines() | endif
autocmd BufWritePost * if g:imager#enabled | call s:AddFillerLines() | endif
autocmd ExitPre * if g:imager#enabled | call s:DisableImages() | endif
autocmd ExitPre * if g:imager#used_latex | silent! execute "!rm -rf '" . expand('~') . '/.latex_images' . "'" | endif

" FUNCTION: s:RenderImages() {{{1
function! s:RenderImages()
	if !g:imager#enabled
		return 0
	endif

	if mode() == 't'
		norm! 
	endif

	if substitute(mode(), 'v', '', 'i') != mode()
		let visual_mode = 1
		norm! 
	else
		let visual_mode = 0
	endif

	" Remember the origional window and cursor
	let origional_winid = win_getid()
	norm! mz

	" Generate a new list of images
	" Image list dictionary format: {'row,col':{path, height, <terminal>}}
	let old = g:imager#images
	let g:imager#images = {}

	" Cycle through the windows and call the function to get its images
	windo call s:GenerateImageDict()
	let new = g:imager#images

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
		" Cycle through the new images, and load all new ones
		for q in keys(new)
			" If the new image hasn't been linked to an old one, render it
			if !has_key(new[q], 'terminal')
				" Check if the right number of filler lines are after the image

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
	if line("'z") > 0
		norm! `z
	else
		call cursor(line('$'), 1)
	endif

	if visual_mode
		norm! gv
	endif

	return 1
endfunction
" }}}

" FUNCTION: s:EnableImages() {{{1
function! s:EnableImages()
	let g:imager#enabled = 1

	if !exists('g:terminal_buffer')
		let origional_buffer = bufnr()
		enew
		let g:terminal_buffer = bufnr()
		execute origional_buffer . 'buffer'
	endif

	" Hide the text for defining images
	set concealcursor=nivc
	syntax match imagerDefinition /^\s*\zs.*<< *img path=".\+" height=\d\+ *>>.*$/ conceal
	syntax match imagerDefinition /^\s*\zs.*<< *img height=\d\+ path=".\+" *>>.*$/ conceal
	syntax match latexDefinition /^\s*\zs.*<< *tex formula=".\+" height=\d\+ *>>.*$/ conceal
	syntax match latexDefinition /^\s*\zs.*<< *tex height=\d\+ formula=".\+" *>>.*$/ conceal
	syntax match imagerFiller /<<imgline>>$/ conceal
	setlocal conceallevel=1
	setlocal concealcursor=nvic

	function! TimerHandler(timer)
		if s:IsWindowChanged()
			call s:RenderImages()
		endif
	endfunction

	call s:AddFillerLines()

	let g:tiler#timer = timer_start(g:imager#timer_delay, 'TimerHandler', {'repeat':-1})
endfunction
" }}}
" FUNCTION: s:DisableImages() {{{1
function! s:DisableImages()
	let g:imager#enabled = 0

	" Show the text for defining images
	syntax match imagerDefinition /^\s*\zs.*<< *img path=".\+" height=\d\+ *>>.*$/
	syntax match imagerDefinition /^\s*\zs.*<< *img height=\d\+ path=".\+" *>>.*$/
	syntax match latexDefinition /^\s*\zs.*<< *tex formula=".\+" height=\d\+ *>>.*$/
	syntax match latexDefinition /^\s*\zs.*<< *tex height=\d\+ formula=".\+" *>>.*$/
	syntax match imagerFiller /<<imgline>>$/ conceal

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

" FUNCTION: s:IsWindowChanged() {{{1
" Detect if there are changes to the current window
function! s:IsWindowChanged()
	" Check if the cursor has moved or the file has changed
	let properties = [{'name':'winid', 'command':'win_getid()'},
				\ {'name':'file', 'command':'expand("%:p")'},
				\ {'name':'winid', 'command':'win_getid()'},
				\ {'name':'buffer', 'command':'bufnr()'},
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
" FUNCTION: s:IsBufferEnabled(bufnr) {{{1
function! s:IsBufferEnabled(bufnr)
	if g:imager#all_filetypes
		return 1
	elseif bufname(a:bufnr) == ''
		return 0
	endif

	let name = split(bufname(a:bufnr), '/')[-1]
	let name_split = split(name, '\.')

	if len(name_split) > 1 && index(g:imager#filetypes, name_split[-1]) > -1
		return 1
	else
		return 0
	endif
endfunction
" }}}
" FUNCTION: s:IsLineImage(string) {{{1
function! s:IsLineImage(string)
	if a:string == ''
		return 0
	elseif substitute(a:string, '.*<< *img path=".\+" height=\d\+ *>>.*$', '', '') == '' ||
				\ substitute(a:string, '.*<< *img height=\d\+ path=".\+" *>>.*$', '', '') == ''
		return 1
	else
		return 0
	endif
endfunction
" }}}
" FUNCTION: s:IsLineLatex(string) {{{1
function! s:IsLineLatex(string)
	if a:string == ''
		return 0
	elseif substitute(a:string, '.*<< *tex formula=".\+" height=\d\+ *>>.*$', '', '') == '' ||
				\ substitute(a:string, '.*<< *tex height=\d\+ formula=".\+" *>>.*$', '', '') == ''
		return 1
	else
		return 0
	endif
endfunction
" }}}

" FUNCTION: s:GenerateImageDict() {{{1
function! s:GenerateImageDict()
	if !s:IsBufferEnabled(bufnr())
		return 0
	endif

	let window_images = s:GetWindowImages()

	" Add all of the values from the function to the master dictionary
	for q in window_images
		if q.shown
			let coords = screenpos(winnr(), q.line, 1)

			" If the image is shown, but screenpos is 0, it starts above the buffer
			if coords.row == 0
				let coords = screenpos(0, line('w0'), 1)
				let coords.row -= line('w0') - q.line
			endif

			let coord_string = coords.row . ',' . string(coords.col + q.indent - 1)
			let g:imager#images[coord_string] = q
		endif
	endfor
endfunction
" }}}
" FUNCTION: s:GetWindowImages() {{{1
function! s:GetWindowImages()
	" Create a list
	let images = []

	let top_window = screenpos(0, line('w0'), 1).row == 1
	let bottom_window = screenpos(0, line('w$'), 1).row == &lines

	" Search the displayed lines
	let first_line = max([1, line('w0')])
	let last_line = line('w$')
	for i in range(1, line('$'))
		let line = getline(i)
		" Check if the line matches one of the valid image formats
		if s:IsLineImage(line) || s:IsLineLatex(line)
			" Create a new blank dictionary for the image
			let new_image = {}

			" Parse the image path, only for images
			if s:IsLineImage(line)
				let path = substitute(line, '^.*path="\(.\+\)".*$', '\1', 'i')

				" If the path starts with dots, add a new parent directory for each
				let parents = 0
				if path != '' && substitute(path, '\.\+\/.*', '', '') == ''
					for q in split(path, '\zs')
						if q == '.'
							let parents += 1
							continue
						endif
						break
					endfor
				elseif path[0] != '~' && path[0] != '/'
					let parents = 1
					let path = './' . path
				endif

				" Calculate the directory based on the number of dots there were
				if parents > 0
					let new_image.path = expand('%:p' . repeat(':h', parents)) . path[parents:-1] 
				endif

				" For Latex formulas only, create a new image using tex2im
			elseif s:IsLineLatex(line)
				let g:imager#used_latex = 1
				let formula = substitute(line, '^.*formula="\(.\+\)".*$', '\1', 'i')

				" Figure out what would be the directory and image paths
				let dir_path = expand('~') . '/.latex_images'
				let image_path = dir_path . '/begin-' . formula . '-end.png'

				" Create the latex directory if it doesn't already exist
				if !system('[ -d "' . dir_path . '" ] && echo 1')
					silent! execute '!mkdir "' . dir_path . '"'
				endif

				" Create the latex image if it doesn't already exist
				if !system('[ -e ' . "'" . image_path . "'" . ' ] && echo 1')
					silent! execute "!tex2im '" . formula . "'"
					silent! execute printf("!mv '%s/out.png' '%s'", getcwd(), image_path)
				endif
				let new_image.path = image_path
			endif

			" Parse the data from the line, and add it to the window image list
			let new_image.height = str2nr(substitute(line, '^.*height=\(\d\+\).*$', '\1', 'i'))

			" Add data about the location of the image
			let new_image.line = i
			let new_image.indent = indent(i)

			" Detect if the image should be displayed
			let top_line = top_window ? line('w0') - new_image.height : line('w0')
			let bottom_line = bottom_window ? line('w$') + new_image.height : line('w$')
			if i > top_line && i < bottom_line && foldclosed(i) <= 0
				let new_image.shown = 1
			else
				let new_image.shown = 0
			endif

			" Add the image to the image list
			call add(images, new_image)
		endif
	endfor

	return images
endfunction
" }}}

" FUNCTION: s:ShowImage(x, y, dict) {{{1
" Display a single image at a certain terminal position
function! s:ShowImage(path, x, y, height)
	let origional_winid = win_getid()

	" Format the command to execute
	let identifier = getpid() . '-' . g:imager#max_id
	let g:imager#max_id += 1

	let command = printf("%s %s '%s' %s %s %s", g:imager#ueberzug_path, identifier, a:path, a:x, a:y, a:height)
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

" FUNCTION: s:AddFillerLines() {{{1
function! s:AddFillerLines()
	" Remember the origional location
	let origional_buffer = bufnr()
	norm! mz

	" Cycle through windows, and if it has images run the function
	for i in range(1, bufnr('$'))
		if s:IsBufferEnabled(i)
			execute i . 'buffer'
			let images = s:GetWindowImages()
			let added_lines = 0

			for q in images
				" Set the indent string
				if &expandtab
					let indent_string = repeat(' ', q.indent)
				else
					let indent_string = repeat('	', q.indent / &shiftwidth)
				endif

				call append(q.line + added_lines, repeat([indent_string . '<<imgline>>'], q.height - 1))
				let added_lines += q.height - 1
			endfor
		endif
	endfor

	" Return to the origional location
	execute origional_buffer . 'buffer'
	if line("'z") > 0
		norm! `z
	else
		call cursor(line('$'), 1)
	endif
endfunction
" }}}
" FUNCTION: s:RemoveFillerLines() {{{1
function! s:RemoveFillerLines()
	" Set a mark at the origional cursor position
	norm! mz

	" Remove all filler lines from all windows
	silent! windo %s/\s*<<imgline>>\n//

	" Return to the origional cursor position
	if line("'z") > 0
		norm! `z
	else
		call cursor(line('$'), 1)
	endif
endfunction
" }}}
