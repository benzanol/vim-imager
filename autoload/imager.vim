" FUNCTION: imager#RenderImages() {{{1
function! imager#RenderImages()
	let cursor_position = [line('.'), col('.')]

	let new_windows = s:GetImageList()
	for winid in s:Union([keys(g:imager#windows), keys(new_windows)])
		" The information about the old window

		" If the window no longer exists, kill all of its images
		if !has_key(new_windows, winid)
			for q in keys(g:imager#windows[winid])
				let g:ter = g:imager#windows[winid][q]
				call s:KillImage(g:imager#windows[winid][q].terminal)
			endfor
			continue

			" If a new window exists, load all of its images
		elseif !has_key(g:imager#windows, winid)
			let new = new_windows[winid]
			call s:ShowWindowImages({}, new.images, winid)
			continue
		endif

		" If the window exists in both lists, go on to compare them
		let new = new_windows[winid]
		let old = g:imager#windows[winid]

		" If all of the properties match, display new images and kill old ones
		if s:WindowUnchanged(old, new)
			call s:ShowWindowImages(old.images, new.images, winid)

			" If not all of the properties match, completely rerender the images
		else
			for q in keys(old.images)
				call s:KillImage(old.images[q].terminal)
			endfor

			call s:ShowWindowImages({}, new.images, winid)
		endif
	endfor

	let g:imager#windows = new_windows

	call cursor(cursor_position)
endfunction
" }}}

" Private functions
" FUNCTION: s:GetImageList() {{{1
function! s:GetImageList()
	" Store information required for displaying images of each window
	let image_list = {}

	" Remember the origional window
	let origional_winid = win_getid()

	" Loop through all windows, and check the buffer for images if the window is
	" of a valid filetype
	for window in range(1, winnr('$'))
		" Go to the window
		let winid = win_getid(window)
		call win_gotoid(winid)

		" Get the window name
		let name_split = split(expand('%:t'), '\.')

		" Get the list of images for the window if it is a valid filetype
		if len(name_split) > 1 && index(g:imager#filetypes, name_split[-1]) > -1

			" Get information about the window itself
			let image_list[winid] = {}

			let screenpos = win_screenpos(0)
			let image_list[winid].x = screenpos[1]
			let image_list[winid].y = screenpos[0]

			let image_list[winid].first = line('w0')
			let image_list[winid].height = line('w$') - line('w0') + 1

			" Add the list of visible images to the dictionary
			let image_list[winid].images = s:GetWindowImages()
		endif
	endfor

	call win_gotoid(origional_winid)

	return image_list
endfunction
" }}}
" FUNCTION: s:GetWindowImages() {{{1
function! s:GetWindowImages()
	" Create a list
	let image_dict = {}

	" Search the displayed lines
	let first_line = max([1, line('w0')])
	let last_line = line('w$')
	for i in range(first_line, last_line)
		let line = getline(i)

		" Check if the line contains !img to signify that it is an image
		if line != '' && substitute(line, '.*!img path:".\+" height:\d\+$', '', 'i') == ''
			" Parse the data from the line, and add it to the window image list
			let path = substitute(line, '^.*path:"\(.\+\)" .*$', '\1', 'i')
			let height = str2nr(substitute(line, '^.*height:\(\d\+\)$', '\1', 'i'))
			let image_dict[i] = {'path':path, 'height':height}
		endif
	endfor

	return image_dict
endfunction
" }}}

" FUNCTION: s:ShowWindowImages(old, new, x, y, first, height) {{{1
function! s:ShowWindowImages(old, new, winid)
	" Loop through the old images looking for images to kill
	for image in keys(a:old)
		" If the image doesnt exists in the new list, or is different, migrate
		" the terminal info to the new image list
		if has_key(a:new, image) && s:ImageUnchanged(a:old[image], a:new[image])
			let a:new[image].terminal = a:old[image].terminal

			" Kill the image if it is not in the new images, or it is different
		else
			call s:KillImage(a:old[image].terminal)
		endif
	endfor

	" Loop through the new images looking for images to load
	for image in keys(a:new)
		" Only load the image if it doesn't have a terminal specified, otherwise
		" it is already loaded
		if !has_key(a:new[image], 'terminal')
			let path = a:new[image].path
			let height = a:new[image].height
			let screenpos = screenpos(a:winid, image, 1)
			let x = screenpos.col - 1
			let y = screenpos.row - 1

			let a:new[image].terminal = s:ShowImage(path, x, y, height)
		endif
	endfor
endfunction
" }}}
" FUNCTION: s:ShowImage(path, x, y, height) {{{1
" Display a single image at a certain terminal position
function! s:ShowImage(path, x, y, height)
	let g:n = [a:path, a:x, a:y, a:height]
	let origional_buffer = bufnr()

	" Set the command to execute to open the image
	let command = 'show-image ' . a:path . ' ' . a:x . ' ' . a:y . ' 1000000 ' . a:height

	" Run the command in a terminal in a new tab, then close it
	execute 'terminal ' . command
	let terminal_buffer = bufnr()

	" Return to the origional buffer
	execute origional_buffer . 'buffer'

	return terminal_buffer
endfunction
" }}}

" FUNCTION: s:WindowUnchanged(old, new) {{{1
function! s:WindowUnchanged(old, new)
	for property in ['x', 'y', 'first', 'height']
		if a:old[property] != a:new[property]
			return 0
		endif
	endfor
	return 1
endfunction
" }}}
" FUNCTION: s:ImageUnchanged(old, new) {{{1
function! s:ImageUnchanged(old, new)
	for property in ['height', 'path']
		if a:old[property] != a:new[property]
			return 0
		endif
	endfor
	return 1
endfunction
" }}}
" FUNCTION: s:KillImage(terminal) {{{1
function! s:KillImage(terminal)
	execute a:terminal . 'bdelete!'
endfunction
" }}}

" FUNCTION: s:Union(lists) {{{1
function! s:Union(lists)
	let union = []

	for q in a:lists
		for r in q
			if index(union, r) == -1
				call add(union, r)
			endif
		endfor
	endfor

	return union
endfunction
" }}}
