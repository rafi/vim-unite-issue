
" vim-unite-issue - Issue tracker and timer for Vim
" Maintainer: Benjamin Roesler <ben.roesler at gzevd dot com>
" License: MIT license
"-------------------------------------------------

let s:save_cpo = &cpo
set cpo&vim

" {{{ Global default settings for Redmine
" My version of redmine does not allow a limit greater than 100
if ! exists('g:unite_source_issue_redmine_limit')
	let g:unite_source_issue_redmine_limit = 100
endif

if ! exists('g:unite_source_issue_redmine_request_header')
	let g:unite_source_issue_redmine_request_header = {}
endif
" }}}

" {{{ Private Request header
let s:redmine_request_header = {
	\ 'User-Agent': 'unite-issue',
	\ 'Content-type': 'application-json',
	\ 'X-Redmine-API-Key': g:redmine_api_key
\ }
" }}}

" {{{ Public methods
function! issue#provider#redmine#fetch_issues(arg, context, roster)
	" Check if variables are set
	if ! exists('g:redmine_url') || ! exists('g:redmine_api_key')
		call unite#print_source_error(
			\ 'unite-issue requires `g:redmine_url` and `g:redmine_api_key` variables',
			\ 'issue'
		\ )
	endif

	" Use Unite's context object to look for a custom query
	let query = get(a:context, 'query', '')
	if len(query) == 0
		let query = s:redmine_build_query({
			\ 'limit': g:unite_source_issue_redmine_limit,
			\ 'assigned_to_id': 'me',
			\ 'status_id': 'open'
		\ })
	endif

	" Fetching the issues
	call unite#print_source_message('Fetch Redmine: ' . query, 'issue')
	let response = s:fetch_issues(query)
	if has_key(response, 'error')
		call unite#print_source_error('Error occured: ' . response.error, 'issue')
	endif
	return s:parse_issues(response.issues, a:roster)
endfunction

function! issue#provider#redmine#highlight()
	syntax match uniteSource__Issue_Key /\d\+/
				\ contained containedin=uniteSource__Issue
	highlight default link uniteSource__Issue_Key Constant
endfunction
" }}}

" {{{ Private methods
function! s:redmine_build_query(elements, ...)
	let query = ''
	for key in keys(a:elements)
		" prepare query part
		let q_part = ''
		if type(a:elements[key]) == 4
			" a:elements[key] is a dictionary
			let q_part = s:redmine_build_query(a:elements[key])
		elseif type(a:elements[key]) <= 1
			" a:elements[key] is a string or number
			if len(a:elements[key]) != 0
				let q_part = printf('%s=%s', key, a:elements[key])
			endif
		elseif type(a:elements[key]) == 3
			" a:elements[key] is an array
			let q_part = join(a:elements[key], '&')
		endif
		" append to query
		if len(q_part) != 0
			if len(query) != 0
				let query .= '&' . q_part
			else
				let query = q_part
			endif
		endif
	endfor
	"return substitute(query, ' ', '', 'g')
	return query
endfunction

function! s:redmine_query_url(query)
	let base = substitute(g:redmine_url, '/\?$', '', '')
	let query = a:query
	let url = printf('%s/issues.json?%s', base, query)
	return url
endfunction

function! s:redmine_issue_url(key)
	let base = substitute(g:redmine_url, '/\?$', '', '')
	return printf('%s/issues/%s.json?include=children,relations,changesets,journals,watchers', base, a:key)
endfunction

function! s:fetch_issues(query)
	let query = a:query
	let url = s:redmine_query_url(query)
	let headers = s:redmine_request_header
	call extend(headers, g:unite_source_issue_redmine_request_header)

	let res = webapi#http#get(url, {}, headers)
	if res.status !~ '^2.*'
		return {
			\ 'issues': [],
			\ 'error': 'Failed to fetch Redmine issue list'
		\ }
	endif

	return webapi#json#decode(res.content)
endfunction

function! s:parse_issues(issues, roster)
	let candidates = []
	" id prio status tracker assignee subject
	let format = '%-5S %-7S:%-15S %-12S  %-18S | %S'
	let issues = a:issues
	for issue in issues
		let started = index(a:roster, 'redmine/' . issue.id) >= 0
		let word = printf(format,
			\ started ? '▶ ' . issue.id : issue.id,
			\ issue#str_trunc(issue.priority.name, 7),
			\ issue#str_trunc(issue.status.name, 15),
			\ issue#str_trunc(issue.tracker.name, 12),
			\ issue#str_trunc(issue.assigned_to.name, 18),
			\ issue.subject,
		\ )
		let item = {
			\ 'word': word,
			\ 'source': 'issue',
			\ 'source__issue_info': {
				\ 'repo': 'redmine',
				\ 'key': issue.id,
				\ 'url': g:redmine_url . '/issues/' . issue.id,
				\ 'fetch_issue': function('s:fetch_issue'),
				\ 'fetch_issued_description': function('s:fetch_issue_description')
			\ }
		\ }
		call add(candidates, item)
	endfor
	return candidates
endfunction

function! s:fetch_issue() dict
	let url = s:redmine_issue_url(self.key)
	let headers = s:redmine_request_header
	call extend(headers, g:unite_source_issue_redmine_request_header)
	let res = webapi#http#get(url, {}, headers)

	if res.status !~ '^2.*'
		return [ 'error', 'Failed to fetch Redmine issue' ]
	endif

	let payload = webapi#json#decode(res.content)
	return s:view_issue(payload.issue)
endfunction

function! s:fetch_issue_description() dict
	echo self.key
endfunction

function! s:view_issue(issue)
	let doc = printf('%s / #%s / %s',
		\ a:issue.project.name, a:issue.id, a:issue.subject)
	let doc .= "\n===\n"
	let doc .= printf(
		\ "Status:   %15S   Begin: %15S\n",
		\ a:issue.status.name,
		\ has_key(a:issue, 'start_date') ? a:issue.start_date : '---'
	\ )
	let doc .= printf(
		\ "Priority: %15S   End:   %15S\n",
		\ a:issue.priority.name,
		\ has_key(a:issue, 'due_date') ? a:issue.due_date : '---'
	\ )
	let doc .= printf(
		\ "Assignee: %15S   Done: %15S%%\n",
		\ has_key(a:issue, 'assigned_to') ? a:issue.assigned_to.name : '---',
		\ a:issue.done_ratio
	\ )
	let doc .= printf(
		\ "Category: %15S   Estimated hours: %5.2f\n",
		\ has_key(a:issue, 'category') ? a:issue.category : '---',
		\ has_key(a:issue, 'estimated_hours') ? a:issue.estimated_hours : 0.0
	\ )
	let doc .= printf(
		\ "Fixed version: %10S\n",
		\ has_key(a:issue, 'fixed_version') ? a:issue.fixed_version : '---',
	\ )
	if has_key(a:issue, 'custom_fields')
		for field in a:issue.custom_fields
			let lgth = 25 - len(field.name) - 2
			let tpl = printf("%%S: %%%iS\n", lgth)
			let doc .= printf(tpl , field.name, len(field.value) != 0 ? field.value : '---')
		endfor
	endif
	let doc .= "\n" . substitute(a:issue.description, '\r', '', 'g') . "\n\n"
	if has_key(a:issue, 'journals')
		for entry in a:issue.journals
			let doc .= printf("%S %S\n", entry.created_on, entry.user.name)
			let doc .= "===\n"
			if has_key(entry, 'details')
				for detail in entry.details
					if has_key(detail, 'new_value') && ! has_key(detail, 'old_value')
						let doc .= printf("++ %S: %S\n", detail.name, detail.new_value)
					elseif has_key(detail, 'new_value') && has_key(detail, 'old_value')
						let doc .= printf("~~ %S: %S => %S\n", detail.name, detail.old_value, detail.new_value)
					else
						let doc .= printf("-- %S", detail.name)
					endif
				endfor
				let doc .= "\n"
			endif
			if has_key(entry, 'notes') && len(entry.notes) != 0
				let doc .= printf("%S\n\n", substitute(entry.notes, '\r', '', 'g'))
			endif
		endfor
	endif
	return doc
endfunction
" }}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: set ts=2 sw=2 tw=80 noet :
