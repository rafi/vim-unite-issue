
" vim-unite-issue - Issue tracker and timer for Vim
" Maintainer: Rafael Bodill <justrafi at gmail dot com>
" License: MIT license
"-------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

" Verifying dependencies " {{{
if ! g:loaded_unite
	finish
endif

if ! executable('curl')
	call unite#print_error('unite-issue requires the `curl` command')
endif

" }}}
" Global defaults " {{{
if ! exists('g:unite_source_issue_data_dir')
	let g:unite_source_issue_data_dir = unite#get_data_directory().'/issue'
endif

if ! isdirectory(g:unite_source_issue_data_dir)
	call mkdir(g:unite_source_issue_data_dir, 'p')
endif
" }}}

" Public methods
" --------------
function! issue#roster(...) " {{{
	" Gets or sets the roster list
	"
	let roster_file = g:unite_source_issue_data_dir.'/roster.txt'

	if a:0 > 0
		return writefile(a:1, roster_file)
	elseif filereadable(roster_file)
		return readfile(roster_file)
	else
		return []
	endif
endfunction

" }}}
function! issue#escape_filename(str) " {{{
	" Escapes a string suitable to be a filename
	" Author: github.com/Shougo/unite.vim
	"
	if len(a:str) < 150
		let hash = substitute(substitute(
			\ a:str, ':', '=-', 'g'), '[/\\]', '=+', 'g')
	elseif exists('*sha256')
		let hash = sha256(a:str)
	else
		" Use simple hash.
		let sum = 0
		for i in range(len(a:str))
			let sum += char2nr(a:str[i]) * (i + 1)
		endfor

		let hash = printf('%x', sum)
	endif

	return hash
endfunction

" }}}
function! issue#str_trunc(str, len, ...) " {{{
	let elipsis = &tenc == 'utf-8' ? '…' : '...'
	let str = a:str
	if len(str) > a:len
		if a:0 > 0 && a:1 == 1
			let str = strpart(str, len(str) - a:len-len(elipsis)) . elipsis
		else
			let str = strpart(str, 0, a:len-len(elipsis)) . elipsis
		endif
	endif
	return str
endfunction

" }}}
function! issue#get_path(dict, path) " {{{
	" Gets a path from a dictionary, e.g. 'fields.foo.bar'
	"
	let key_parts = split(a:path, '\.')
	let found = ''
	let value = a:dict
	while len(key_parts) > 0 && found == ''
		let key_part = remove(key_parts, 0)
		if type(get(value, key_part)) == type({})
			let value = get(value, key_part)
		else
			let found = get(value, key_part)
		endif
	endwhile

	return type(found) == type('') ? found : ''
endfunction

" }}}
function! issue#highlight_general() " {{{
	" Defines general issue list highlights
	"
	syntax match uniteSource__Issue_Properties /.*|\s/
				\ contained containedin=uniteSource__Issue
	highlight default link uniteSource__Issue_Properties Function

	" Within properties, match the issues in progress
	syntax match uniteSource__Issue_Started /▶\s\S\+\s/
				\ contained containedin=uniteSource__Issue_Properties
	highlight default link uniteSource__Issue_Started Todo

	" Within properties, match a non-word before a semicolon (e.g. comments)
	syntax match uniteSource__Issue_Count /[^a-z ]\+\ze:/
				\ contained containedin=uniteSource__Issue_Properties
	highlight default link uniteSource__Issue_Count Statement

	" Within properties, match a word after a semicolon (e.g. priority)
	syntax match uniteSource__Issue_Status /:\(\h\+\-\?\s\?…\?\)\{1,3}/
				\ contained containedin=uniteSource__Issue_Properties
	highlight default link uniteSource__Issue_Status PreProc

	" Within properties, match a word before a pipe (e.g. user)
	syntax match uniteSource__Issue_User /\(\h\+\.\?\s\?…\?\)\{1,2}\ze\s*|/
				\ contained containedin=uniteSource__Issue_Properties
	highlight default link uniteSource__Issue_User Special

	" Outside of properties,
	" match everything between brackets towards end of string (e.g. tags)
	syntax match uniteSource__Issue_Labels /\[.\+\]\s*$/
				\ contained containedin=uniteSource__Issue
	highlight default link uniteSource__Issue_Labels Comment
endfunction
" }}}
function! issue#add_comment() " {{{
	" Open a new window for adding a comment, and pass
	" the comment text to the issue provider on write.

	if !exists('w:issue')
		return
	endif

	let issue = w:issue
	let fn = '__comment_' . w:issue.key
	botright 10new `=fn`
	setlocal wrap linebreak nolist cc=0
	setlocal filetype=markdown
	setlocal buftype=acwrite
	setlocal nobuflisted noswapfile
	let w:issue = issue

	autocmd! * <buffer>
	autocmd BufWriteCmd <buffer> call w:issue.add_comment(
		\ join(getline(0,'$'), "\n"))
	autocmd BufWriteCmd <buffer> :q!
endfunction
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
