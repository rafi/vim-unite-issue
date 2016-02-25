
" vim-unite-issue - Issue tracker and timer for Vim
" Maintainer: Rafael Bodill <justrafi at gmail dot com>
" License: MIT license
"-------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

" Defining a new Unite kind " {{{
let s:kind = {
	\ 'name': 'issue',
	\ 'default_action': 'view',
	\ }

let s:kind.action_table = {
	\ 'view': {
	\   'description': 'View issue as Markdown',
	\   'is_quit': 0
	\ },
	\ 'browse': {
	\   'description': 'Open in browser',
	\   'is_quit': 0
	\ },
	\ 'start': {
	\   'description': 'Start timer on issue',
	\   'is_invalidate_cache': 1,
	\   'is_quit': 0
	\ },
	\ 'stop': {
	\   'description': 'Stop timer on issue',
	\   'is_invalidate_cache': 1,
	\   'is_quit': 0
	\ },
	\ }
" }}}

" Public methods
" --------------
function! unite#kinds#issue#define() " {{{
	" Announce this kind so Unite recognizes it.
	"
  return s:kind
endfunction
" }}}

" Private methods
" ---------------
function! s:kind.action_table.browse.func(candidate) " {{{
	" Action: browse
	" Opens a new browser tab with selected issue's link.
	"
	let url = a:candidate.source__issue_info.url
	call openbrowser#open(url)
endfunction

" }}}
function! s:kind.action_table.view.func(candidate) " {{{
	" Action: view
	" Opens the selected issue in a new window, as markdown.
	"
	res 5
	silent execute 'botright new'
	let issue = a:candidate.source__issue_info.fetch_issue()
	silent put =issue
	call s:setup_issue_view(a:candidate.source__issue_info)
	:0
endfunction

" }}}
function! s:kind.action_table.start.func(candidate) " {{{
	" Action: start
	" Starts a timer on a specific issue
	"
	try
		call issue#timer#start(
			\ a:candidate.source__issue_info.repo,
			\ a:candidate.source__issue_info.key)
	catch
		call unite#print_source_error(v:exception, 'issue')
	endtry
endfunction

" }}}
function! s:kind.action_table.stop.func(candidate) " {{{
	" Action: stop
	" Stops a running timer on a specific issue
	"
	try
		call issue#timer#stop(
			\ a:candidate.source__issue_info.repo,
			\ a:candidate.source__issue_info.key)
	catch
		call unite#print_source_error(v:exception, 'issue')
	endtry
endfunction

" }}}
function! s:setup_issue_view(issue) " {{{
	" Setup the issue view buffer.
	"
	setfiletype markdown
	setlocal wrap linebreak nolist cc=0
	setlocal nospell
	setlocal buftype=nofile
	setlocal bufhidden=wipe
	setlocal nobuflisted
	setlocal noswapfile
	setlocal nomodified
	setlocal nomodifiable
	setlocal readonly

	let w:issue = a:issue
	command! -nargs=0 -buffer AddComment call issue#add_comment()
endfunction
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
