
" vim-unite-issue - Issue tracker and timer for Vim
" Maintainer: Rafael Bodill <justrafi at gmail dot com>
" Version:    20141008
"-------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

" Defining a new Unite source interface " {{{
let s:source = {
	\ 'name': 'issue',
	\ 'description': 'Issue tracker',
	\ 'default_kind' : 'source',
	\ 'default_action' : 'view',
	\ 'syntax': 'uniteSource__Issue',
	\ 'hooks': {},
	\ 'action_table': { 'common': {} }
	\ }

let s:source.action_table.common.browse = {
	\ 'description': 'Open in browser',
	\ 'is_selectable': 0,
	\ 'is_quit': 0
	\ }

let s:source.action_table.common.view = {
	\ 'description': 'View issue as Markdown',
	\ 'is_selectable': 0,
	\ 'is_quit': 0
	\ }
" }}}

" Public methods
" --------------
function! unite#sources#issue#define() " {{{
	" Announce this source so Unite recognizes it.
	"
	return s:source
endfunction
" }}}

" Private methods
" ---------------
function! s:source.gather_candidates(args, context) " {{{
	" Gather candidates for Unite source's interface.
	"
	if len(a:args) ==  0
		call unite#print_error('You must specify provider.')
		return []
	endif

	let name = a:args[0]
	if len(a:args) > 1
		let arg = a:args[1]
	else
		let arg = ''
	endif

	return issue#provider#{name}#fetch_issues(arg)
endfunction

" }}}
function! s:source.hooks.on_syntax(args, context) " {{{
	" Sets-up color highlighting for Unite source's interface.
	"
	if len(a:args) ==  0
		return
	endif

	call issue#highlight_general()

	let name = a:args[0]
	call issue#provider#{name}#highlight()
endfunction

" }}}
function! s:source.action_table.common.browse.func(candidate) " {{{
	" Action: browse
	" Opens a new browser tab with selected issue's link.
	"
	let url = a:candidate.source__issue_info.url
	call openbrowser#open(url)
endfunction

" }}}
function! s:source.action_table.common.view.func(candidate) " {{{
	" Action: view
	" Opens the selected issue in a new window, as markdown.
	"
	silent execute 'botright new'
	let issue = a:candidate.source__issue_info.fetch_issue()
	silent put =issue
	call s:setup_issue_view()
	:0
endfunction

" }}}
function! s:setup_issue_view() " {{{
	" Setup the issue view buffer.
	"
	setfiletype mkd
	setlocal buftype=nofile
	setlocal bufhidden=wipe
	setlocal nobuflisted
	setlocal noswapfile
	setlocal nomodified
	setlocal nomodifiable
	setlocal readonly
endfunction

" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
