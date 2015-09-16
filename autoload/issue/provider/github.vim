
" vim-unite-issue - Issue tracker and timer for Vim
" Maintainer: Rafael Bodill <justrafi at gmail dot com>
" License: MIT license
"-------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

" Global default settings for GitHub's data {{{
if ! exists('g:github_url')
	let g:github_url = 'https://api.github.com/'
endif

if ! exists('g:unite_source_issue_github_limit')
	let g:unite_source_issue_github_limit = 100
endif

if ! exists('g:unite_source_issue_github_state_table')
	let g:unite_source_issue_github_state_table = {
		\ 'open': 'open', 'closed': 'closed' }
endif

" }}}
" Private GitHub Request header {{{
let s:github_request_header = {
	\ 'User-Agent': 'unite-issue',
	\ 'Content-type': 'application/json',
	\ 'Authorization': 'Basic '.
	\   webapi#base64#b64encode(g:github_token.':x-oauth-basic')
	\ }
" }}}

" Public methods
" --------------
function! issue#provider#github#fetch_issues(repo, context, roster) " {{{
	" Queries GitHub's Issue API, and parses candidates for Unite.
	"
	if ! exists('g:github_token')
		call unite#print_error('unite-issue requires `g:github_token` variable')
	endif

	let issues = s:fetch_issues(a:repo)
	return s:parse_issues(issues, a:repo, a:roster)
endfunction

" }}}
function! issue#provider#github#highlight() " {{{
	" Defines GitHub's issue number highlight.
	"
	" Match a dash followed by digits
	syntax match uniteSource__Issue_Key /#\d\+\>/
				\ contained containedin=uniteSource__Issue
	highlight default link uniteSource__Issue_Key Constant
endfunction
" }}}

" Private methods
" ---------------
function! s:github_query_url(repo, limit) " {{{
	" Generates a proper GitHub API URL querying list of issues.
	"
	let base = substitute(g:github_url, '/\?$', '', '')
	if len(a:repo) > 0
		let base .= '/repos/'.a:repo
	endif
	return printf('%s/issues', base)
endfunction

" }}}
function! s:github_issue_url(repo, key) " {{{
	" Generates a proper GitHub API URL for issue fetching.
	"
	let url = s:github_query_url(a:repo, g:unite_source_issue_github_limit)
	return url.'/'.a:key
endfunction

" }}}
function! s:github_issue_comments_url(repo, key) " {{{
	" Generates a proper GitHub API URL for issue's comments.
	"
	return s:github_issue_url(a:repo, a:key).'/comments'
endfunction

" }}}
function! s:fetch_issues(repo) " {{{
	" Queries GitHub's Issue API for all opened issues.
	"
	let url = s:github_query_url(a:repo, g:unite_source_issue_github_limit)
	let res = webapi#http#get(url, {}, s:github_request_header)

	if res.status !~ '^2.*'
		return [ 'error', 'Failed to fetch GitHub issue list' ]
	endif

	return webapi#json#decode(res.content)
endfunction

" }}}
function! s:parse_issues(issues, repo, roster) " {{{
	" Parses GitHub's issue list and prepares possible Unite candidates.
	"
	let candidates = []
	for issue in a:issues
		let repo = a:repo
		if len(repo) == 0 && type(issue) == type({}) && has_key(issue, 'repository')
			let repo = issue.repository.full_name
		endif

		let labels = []
		for label in issue.labels
			call add(labels, label.name)
		endfor

		let state = get(g:unite_source_issue_github_state_table,
			\ issue.state, issue.state)
		let started = index(a:roster, a:repo.'/'.issue.number) >= 0

		let word = printf('%-6s %2s:%-5s %-7s | %s %s',
			\ started ? '▶ #'.issue.number : '#'.issue.number,
			\ issue.comments > 0 ? issue.comments : '-',
			\ state,
			\ (type(issue.milestone) == 4 ? issue.milestone.title : ''),
			\ substitute(issue.title, '^\s\+', '', ''),
			\ (len(labels) > 0 ? '['.join(labels, ', ').']' : '')
			\ )

		let item = {
			\ 'word': word,
			\ 'source': 'issue',
			\ 'source__issue_info' : {
			\   'repo': repo,
			\   'key': issue.number,
			\   'url': issue.html_url,
			\   'fetch_issue': function('s:fetch_issue'),
			\  }
			\ }

		call add(candidates, item)
	endfor

	return candidates
endfunction

" }}}
function! s:fetch_issue() dict " {{{
	" Queries GitHub's Issue API for a specific issue.
	"
	let url = s:github_issue_url(self.repo, self.key)
	let res = webapi#http#get(url, {}, s:github_request_header)

	if res.status !~ '^2.*'
		return [ 'error', 'Failed to fetch GitHub issue' ]
	endif
	let issue = webapi#json#decode(res.content)

	let comments = []
	if issue.comments > 0
		let url = s:github_issue_comments_url(self.repo, self.key)
		let res = webapi#http#get(url, {}, s:github_request_header)

		if res.status !~ '^2.*'
			return [ 'error', 'Failed to fetch GitHub issue comments' ]
		endif
		let comments = webapi#json#decode(res.content)
	endif

	return s:view_issue(self.repo, issue, comments)
endfunction

" }}}
function! s:view_issue(repo, issue, comments) " {{{
	" Returns a Markdown representation of issue dictionary.
	"
	let doc = printf('%s / #%s / %s',
		\ a:repo, a:issue.number, a:issue.title)
	let doc .= "\n---\n"
	let table = {
			\ 'Milestone': 'milestone.title',
			\ 'Assignee': 'assignee.login',
			\ 'State': 'state',
			\ 'Locked': 'locked',
			\ 'Created at': 'created_at',
			\ 'Updated at': 'updated_at',
			\ 'Closed at': 'closed_at',
			\ 'Closed by': 'closed_by.login',
			\ }

	let i = 0
	let column_width = 30
	for [ title, path ] in items(table)
		let odd = i % 2 > 0
		let value = issue#get_path(a:issue, path)
		let prop = '['.title.']: '.value
		if odd
			let prop = repeat(' ', column_width - strdisplaywidth(last_prop)).prop."\n"
		else
			let last_prop = prop
		endif
		let doc .= prop
		let i += 1
	endfor

	" Collect labels
	if len(a:issue.labels) > 0
		let labels = []
		for label in a:issue.labels
			call add(labels, label.name)
		endfor
		let doc .= '[Labels]: '.join(labels, ', ')."\n"
	endif

	" Display body of issue
	if len(a:issue.body) > 0
		let doc .= "\nDescription\n-----------\n"
		let doc .= substitute(a:issue.body, "\r", '', 'g')."\n"
	endif

	" Collect comments
	if a:issue.comments > 0
		let doc .= "\nComments\n--------\n"
		for comment in a:comments
			let doc .= printf('_%s_: ', comment.user.login)
				\.substitute(comment.body, "\r", '', 'g')."\n"
		endfor
	endif

	return doc
endfunction
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
