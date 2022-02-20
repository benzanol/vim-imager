" Set default values for user modifiable settings {{{1
" Filetypes to search for images in
let g:imager#filetypes = ['md']

" Whether or not to search for images in all filetypes
let g:imager#all_filetypes = 1

" Set the colors of latex expressions
let g:imager#latex_foreground = 'white'
let g:imager#latex_background = '23272E'

" Whether or not to automatically add and remove filler lines under the image
" when displaying it (has issues)
let g:imager#automatic_filler = 0
" }}}
" Set starting values for global variables {{{1
" Whether or not to show images in place of the image keys
let g:imager#enabled = 0

" The list of currently active images
let g:imager#images = {}

" Increment each time an image is displayed, so each Uberzug session is given
" a unique id
let g:imager#max_id = 1

" How often to check whether any images have been changed
let g:imager#timer_delay = 10

" The path to the ueberzug script
let g:imager#ueberzug_path = expand('<sfile>:p:h:h') . '/ueberzug/load-image.sh'

" Start out not having used latex
let g:imager#used_latex = 0
" }}}
" Initialize commands and autocommands {{{1
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
" }}}
" Initialize global regular expressions {{{1
let s:image_regexp = '.*<< *img path="\([^"]\+\)" height=\(\d\+\) *>>.*$'
let s:latex_regexp = '.*<< *tex formula="\([^"]\+\)" height=\(\d\+\)\( plugins="\([^"]\+\)"\)\? *>>.*$'
" }}}

function! s:RenderImages() " {{{1
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

	" Remember the original window and cursor
	let original_winid = win_getid()
	norm! mz

	" Generate a new list of images
	" Image list dictionary format: {'row,col':{path, height, <terminal>}}
	let old = g:imager#images
	let g:imager#images = {}

	" Cycle through the windows and call the function to get its images
	windo call s:GenerateImageDict()
	let new = g:imager#images

	" Cycle through old images, and remove all inactive ones
    let g:new = new
    let g:old = old
	let any_missing = 0
	for q in keys(old)
		" Migrate the terminal to the new image if there is an identical old one
		if has_key(new, q) && (new[q].path == old[q].path) && (new[q].height == old[q].height)
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

	" Return to the original window and cursor position
	call win_gotoid(original_winid)
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

function! s:EnableImages() " {{{1
	let g:imager#enabled = 1

	" Create a temporary directory for latex images if it doesnt exist
	if !system('[ -d "/tmp/latex_images" ] && echo 1')
		silent! execute '!mkdir "/tmp/latex_images"'
	endif

	" Hide the text for defining images
	syntax match imagerDefinition /^\s*.*<<img path=".\+" height=\d\+>>.*$/ conceal
	syntax match latexDefinition /^\s*.*<<tex formula=".\+" height=\d\+>>.*$/ conceal
	syntax match imagerFiller /^\s*<<imgline>>$/ conceal
	setlocal conceallevel=1
	setlocal concealcursor=nvic

	" Function for constantly checking whether to refresh images
	function! TimerHandler(timer)
		if s:IsWindowChanged()
			call s:RenderImages()
		endif
	endfunction

	call s:AddFillerLines()

	let g:imager#timer = timer_start(g:imager#timer_delay, 'TimerHandler', {'repeat':-1})

	call s:RenderImages()

	" Return that images are now enabled
	redraw!
	echo 'Imager has now been enabled'
endfunction
" }}}
function! s:DisableImages() " {{{1
	let g:imager#enabled = 0

	" Show the text for defining images
	syntax match imagerDefinition /^\s*.*<<img path=".\+" height=\d\+>>.*$/
	syntax match latexDefinition /^\s*.*<<tex formula=".\+" height=\d\+>>.*$/
	syntax match imagerFiller /^\s*<<imgline>>$/

	" Kill all existing images
	for q in keys(g:imager#images)
		call s:KillImage(g:imager#images[q].terminal)
	endfor

	let g:imager#images = {}
	call s:RemoveFillerLines()

	" Return that images are now disabled
	redraw!
	echo 'Imager has now been disabled'
endfunction
" }}}
function! s:ReloadImages() " {{{1
	if g:imager#enabled
		call s:DisableImages()
	endif
	call s:EnableImages()
endfunction
" }}}
function! s:ToggleImages() " {{{1
	if g:imager#enabled
		call s:DisableImages()
	else
		call s:EnableImages()
	endif
endfunction
" }}}

function! s:IsWindowChanged() " {{{1
	" Check if the cursor has moved or the file has changed
	let properties = [{'name':'winid', 'command':'win_getid()'},
				\ {'name':'file', 'command':'expand("%:p")'},
				\ {'name':'winid', 'command':'win_getid()'},
				\ {'name':'buffer', 'command':'bufnr()'},
				\ {'name':'window_position', 'command':'win_screenpos(winnr())'},
				\ {'name':'window_size', 'command':'winwidth(0) . "," . winheight(0)'},
				\ {'name':'window_lines', 'command':'line("w0") . "," . line("w$")'},
				\ {'name':'line_rows', 'command':'screenpos(0, line("w0"), 1).row . "," . screenpos(0, line("w$"), 1).row'},
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
function! s:IsBufferEnabled(bufnr) " {{{1
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

function! s:GenerateImageDict() " {{{1
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

			let coord_string = coords.row . ',' . string(coords.col + q.indent)
			let g:imager#images[coord_string] = q
		endif
	endfor
endfunction
" }}}
function! s:GetWindowImages() " {{{1
	" Create a list
	let images = []

	let top_window = screenpos(0, line('w0'), 1).row == 1
	let bottom_window = screenpos(0, line('w$'), 1).row == &lines

	" Search the displayed lines
	let first_line = max([1, line('w0')])
	for i in range(1, line('$'))
		let line = getline(i)

		" Check if the line matches one of the valid image formats
		let image_attributes = split(substitute(line, s:image_regexp, '\1\n\2', ''), "\n")
		let latex_attributes = split(substitute(line, s:latex_regexp, '\1\n\2\n\3', ''), "\n")
		let is_image = len(image_attributes) > 1
		let is_latex = len(latex_attributes) > 1

		if is_image || is_latex
			" Create a new blank dictionary for the image
			let new_image = {}

			" Parse the image path, only for images
			if is_image
				let path = image_attributes[0]

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
                else
                    let new_image.path = path
				endif

				" For Latex formulas only, create a new image using tex2im
			elseif is_latex
				let formula = latex_attributes[0]
				if len(latex_attributes) > 2
					let latex_package = split(latex_attributes[2], ',')
					let snippet_string = join(latex_packages, ',') . ':' . formula
				else
					let snippet_string = formula
				endif
				let hash = split(system(printf('echo -n "%s" | md5sum', snippet_string)), ' ')[0]

				" Figure out what would be the directory and image paths
				let dir_path = '/tmp/latex_images'
				let image_path = dir_path . '/' . hash . '.png'

				" Create the latex image if it doesn't already exist
				if !system('[ -e ' . "'" . image_path . "'" . ' ] && echo 1')
					" If the foreground or background colors are a hex value, add HTML:
					" before them to make the hex code valid
					let foreground = g:imager#latex_foreground
					let background = g:imager#latex_background
					if substitute(g:imager#latex_foreground, '\x\{6}', '', '') == ''
						let foreground = 'HTML:' . foreground
					endif
					if substitute(g:imager#latex_background, '\x\{6}', '', '') == ''
						let background = 'HTML:' . background
					endif

					" Generate the preamble text to use certain plugins
					if exists('latex_packages')
						let preamble = '-x \usepackage{' .
									\ join(latex_packages, "}\\usepackage{") .
									\ '} '
					else
						let preamble = ''
					endif

					" Convert the latex expression into an image
					silent! execute printf("!tex2im %s-b %s -t %s '%s'", preamble, background, foreground, formula)
					silent! execute printf("!mv '%s/out.png' '%s'", getcwd(), image_path)
				endif
				let new_image.path = image_path
			endif

			" Parse the data from the line, and add it to the window image list
			let new_image.height = is_image ? image_attributes[1] : latex_attributes[1]

			" Add data about the location of the image
			let new_image.line = i
			let new_image.indent = indent(i)

			" Detect if the image should be displayed
			let top_line = top_window ? line('w0') - new_image.height : line('w0')
			let bottom_line = bottom_window ? line('w$') + new_image.height : line('w$')
			if i >= top_line && i <= bottom_line && foldclosed(i) <= 0
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

function! s:ShowImage(path, x, y, height) " {{{
	" Display a single image at a certain terminal position
	let original_winid = win_getid()

	" Format the command to execute
	let g:imager#max_id += 1

	let command = printf("bash %s '%s' %s %s %s", g:imager#ueberzug_path, a:path, a:x, a:y, a:height)

	" Run the command in a terminal in a new tab, then close it
	new
	call termopen(command)
	setlocal nobuflisted
	let terminal_buffer = bufnr()
	close!

	" Return to the original buffer
	call win_gotoid(original_winid)

	return terminal_buffer
endfunction
" }}}
function! s:KillImage(terminal) " {{{1
	execute a:terminal . 'bdelete!'
endfunction
" }}}

function! s:AddFillerLines() " {{{1
	" If adding automatic filler lines is disabled, return before doing anything
	if !g:imager#automatic_filler
		return
	endif

	" Remember the original location
	let original_buffer = bufnr()
	norm! mz

	" Cycle through windows, and if it has images run the function
	for i in range(1, bufnr('$'))
		if bufexists(i) && s:IsBufferEnabled(i)
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

	" Return to the original location
	execute original_buffer . 'buffer'
	if line("'z") > 0
		norm! `z
	else
		call cursor(line('$'), 1)
	endif
endfunction
" }}}
function! s:RemoveFillerLines() " {{{1
	" If adding automatic filler lines is disabled, return before doing anything
	if !g:imager#automatic_filler
		return
	endif

	" Set a mark at the original cursor position
	norm! mz

	" Remove all filler lines from all windows
	silent! windo %s/\s*<<imgline>>\n//

	" Return to the original cursor position
	if line("'z") > 0
		norm! `z
	else
		call cursor(line('$'), 1)
	endif
endfunction
" }}}
