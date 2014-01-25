function! pymport#warn(msg) abort "{{{
  echohl WarningMsg
  echo 'pymport: '.a:msg
  echohl None
endfunction "}}}

" generate an absolute path name and strip a trailing /
function! pymport#normalize_path(path) abort "{{{
  let path = fnamemodify(a:path, ':p')
  if path[-1:] == '/'
    let path = path[:-2]
  endif
  return path
endfunction "}}}

" convert a file path to a dotted module path relative to a:basedir
function! pymport#module(path, basedir) abort "{{{
  let path = pymport#normalize_path(a:path)
  let basedir = pymport#normalize_path(a:basedir)
  let prefix_len = len(basedir)
  if path[:prefix_len-1] == basedir
    let path = path[prefix_len+1:]
  endif
  let path = matchstr(path, '^\zs.\{-}\ze\(__init__\)\?\.py$')
  if path[-1:] == '/'
    let path = path[:-2]
  endif
  return substitute(path, '/', '.', 'g')
endfunction "}}}

function! pymport#greplike(cmdline, name, path) abort "{{{
  let files = []
  let keywords = '^(class|def)'
  if filereadable(a:path) || isdirectory(a:path)
    let cmd = printf(a:cmdline, keywords, a:name, a:path)
    let output = system(cmd)
    for line in split(output, '\n')
      let fields = split(line, ':')
      call add(files, {
            \ 'path': fields[0],
            \ 'lineno': fields[1],
            \ 'content': fields[2],
            \ 'module': pymport#module(fields[0], a:path),
            \ })
    endfor
  endif
  return files
endfunction "}}}

function! pymport#grep(name, path) abort "{{{
  return pymport#greplike("grep -n -E -r --include='*.py' '%s %s\\(' %s", a:name, a:path)
endfunction "}}}

function! pymport#ag(name, path) abort "{{{
  return pymport#greplike('ag -G "\.py$" "%s %s\(" %s', a:name, a:path)
endfunction "}}}

" aggregate search results from all locations in g:pymport_paths
function! pymport#locations(name) abort "{{{
  let locations = []
  for path in g:pymport_paths
    let locations += call(g:pymport_finder, [a:name, path])
  endfor
  return locations
endfunction "}}}

function! pymport#prompt_format(index, file) abort "{{{
  return '['. (a:index+1) .'] '.a:file['module'] .':'.a:file['lineno'] .'  '.
        \ a:file['content']
endfunction "}}}

" select an element of a:files by user input
function! pymport#prompt(files) abort "{{{
  let lines = ['Multiple matches:'] +
        \ map(copy(a:files), 'pymport#prompt_format(v:key, v:val)')
  let choice = inputlist(lines)
  return choice > '0' ? a:files[choice-1] : {}
endfunction "}}}

" prompt the user to select a module if the name was found in more than one
function! pymport#choose(files) abort "{{{
  return len(a:files) > 1 ? pymport#prompt(a:files) : a:files[0]
endfunction "}}}

" return the module's part before the first '.'
function! pymport#package(module) abort "{{{
  return split(a:module, '\.')[0]  
endfunction "}}}

" find the position at which to insert a new package block according to
" g:pymport_package_precedence. the first element will be placed at the
" bottom.
function! pymport#block_insertion_line(imports, package) abort "{{{
  let packages = g:pymport_package_precedence
  let position = index(packages, a:package)
  if position == -1
    let position = len(packages)
  endif
  let index = -1
  for package in packages[:position]
    while (index > 1 - len(a:imports)) &&
          \ pymport#package(a:imports[index][1]) == package
      let index -= 1
    endwhile
  endfor
  return index == len(a:imports) ? 0 : a:imports[index][0]
endfunction "}}}

" find the import using the exact target module or the last one matching the
" target's package. return also an indicator if the module should be appended
" to the line (1) or the import block (0) or placed separate (-1)
function! pymport#best_match(imports, module) abort "{{{
  let package = pymport#package(a:module)
  let last = get(a:imports, -1, [0])[0]
  let best = len(a:imports) > 0 ? [last, -1] : [0, 0]
  for entry in a:imports
    if a:module == entry[1] && getline(entry[0]) =~ '^from'
      let best = [entry[0], 1]
      break
    elseif pymport#package(entry[1]) == package
      let best = [entry[0], 0]
    endif
  endfor
  if best[1] == -1
    let best[0] = pymport#block_insertion_line(a:imports, package)
  endif
  return best
endfunction "}}}

" TODO skip lines with 'as'
" collect all top level import statements and call the matching function
function! pymport#target_location(target, name) abort "{{{
  let imports = []
  function! Adder(imports) abort "{{{
    call add(a:imports, [line('.'), split(getline('.'))[1]])
  endfunction "}}}
  silent global /\%(^from\|import\) / call Adder(imports)
  let @/ = ''
  return pymport#best_match(imports, a:target['module'])
endfunction "}}}

" find the end of a single or multi line import by checking for parentheses
function! pymport#goto_end_of_import(lineno) abort "{{{
  execute a:lineno.' normal! $'
  call searchpair('(', '', ')')
endfunction "}}}

" surround the imported names with parentheses
function! pymport#add_parentheses(lineno) abort "{{{
  execute a:lineno .'substitute /import \zs.*/(&)'
  let @/ = ''
endfunction "}}}

" format the change if it causes a line to exceed 'textwidth'
function! pymport#format(lineno, lineno_end) abort "{{{
  execute a:lineno.','.a:lineno_end.' join'
  let line = getline(a:lineno)
  if len(line) > &textwidth
    if line !~ 'import (.*)'
      call pymport#add_parentheses(a:lineno)
    endif
    execute a:lineno 'normal! gqq'
  endif
endfunction "}}}

" TODO skip existing imports
function! pymport#deploy(lineno, exact, target, name) abort "{{{
  let import = 'from '.a:target['module'] .' import '. a:name
  if a:lineno == 0
    0 put =''
    0 put =import
  else
    call pymport#goto_end_of_import(a:lineno)
    if a:exact == 1
      keepjumps substitute /\()\?\)$/\=', '.a:name .submatch(1)/
      let @/ = ''
      call call(g:pymport_formatter, [a:lineno, line('.')])
    else
      if a:exact == -1
        put =''
      endif
      put =import
    endif
  endif
endfunction "}}}

" determine all candidates and query the user if more than one was found
function! pymport#resolve(name) abort "{{{
  let target = {}
  let files = pymport#locations(a:name)
  if len(files) > 0
    let target = pymport#choose(files)
  endif
  return target
endfunction "}}}

" find the appropriate spot for the import and deploy it
function! pymport#process(target, name) abort "{{{
  let [lineno, exact] = call(g:pymport_target_locator, [a:target, a:name])
  return pymport#deploy(lineno, exact, a:target, a:name)
endfunction "}}}

" main function
" The initial location is remembered in the ` mark and navigated to in the
" end. As this method leaves one entry at that same position on the jump
" stack, a <c-o> keypress is simulated.
" TODO implement a method to determine where imports should begin (e.g. after
" docstring)
function! pymport#import(name) abort "{{{
  normal! m`
  let target = pymport#resolve(a:name)
  if len(target) > 0
    call pymport#process(target, a:name)
  else
    call pymport#warn('No match for "'.a:name.'"!')
  endif
  keepjumps normal! ``
  call feedkeys("\<c-o>")
endfunction "}}}
