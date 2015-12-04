
" vim-unite-issue - Issue tracker and timer for Vim
" Maintainer: Rafael Bodill <justrafi at gmail dot com>
" License: MIT license
"-------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

" Defining a new Unite source interface " {{{
let s:source = {
	\ 'name': 'issue',
	\ 'description': 'Issue tracker',
	\ 'default_kind' : 'issue',
	\ 'default_action' : 'view',
	\ 'syntax': 'uniteSource__Issue',
	\ 'hooks': {}
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
		call unite#print_source_error('You must specify provider.', 'issue')
		return []
	endif

	" Use the 1st argument as the provider's name,
	" and the 2nd argument as an optional custom argument.
	let provider_name = a:args[0]
	if len(a:args) > 1
		let arg = a:args[1]
	else
		let arg = ''
	endif

	let roster = issue#roster()

	" Also provide the context object for any custom arguments needed
	return issue#provider#{provider_name}#fetch_issues(arg, a:context, roster)
endfunction

" }}}
function! s:source.hooks.on_syntax(args, context) " {{{
	" Sets-up color highlighting for Unite source's interface.
	"
	if len(a:args) ==  0
		return
	endif

	call issue#highlight_general()

	let provider_name = a:args[0]
	call issue#provider#{provider_name}#highlight()
endfunction

" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
