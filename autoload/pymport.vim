function! pymport#warn(msg) abort "{{{
  echohl WarningMsg
  echo 'pymport: '.a:msg
  echohl None
endfunction "}}}

function! pymport#system(cmd) abort "{{{
  if exists(':VimProcRead')
    return vimproc#system(a:cmd)
  else
    return system(a:cmd)
  endif
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

" return output of the a:cmdline greplike process searching for pattern in
" path as a list of lines
function! pymport#greplike(cmdline, pattern, path) abort "{{{
  let lines = []
  if filereadable(a:path) || isdirectory(a:path)
    let cmd = printf("%s '%s' %s", a:cmdline, a:pattern, a:path)
    let lines = split(pymport#system(cmd), '\n')
  endif
  return lines
endfunction "}}}

function! pymport#grep(pattern, path) abort "{{{
  let output = pymport#greplike("grep -n -E -r --include='*.py'",
        \ a:pattern, a:path)
  return map(output, 'split(v:val, '':''[:2])')
endfunction "}}}

function! pymport#ag(pattern, path) abort "{{{
  let output = pymport#greplike(g:pymport_ag_cmdline, a:pattern, a:path)
  function! Split(line) abort "{{{
    let parts = split(a:line, ':')
    return parts[:1] + [parts[2]]
  endfunction "}}}
  return map(output, 'Split(v:val)')
endfunction "}}}

" search all __init__ modules starting at a:basedir for forward imports of
" a:name from a:module.
function! pymport#forward_module(basedir, module, name) abort "{{{
  let path = a:basedir
  let components = split(a:module, '\.')
  let pattern = '\s*from .*\.' . components[-1] . ' import .*(\b' . a:name .
        \ '\b|\*)'
  let module = ''
  for component in components[:-2]
    let module = module . component . '.'
    let path = path . '/' . component
    let file = path . '/__init__.py'
    if len(call(g:pymport_finder, [pattern, file]))
      return module[:-2]
    endif
  endfor
  return a:module
endfunction "}}}

" extract the module path relative to a:basedir from a:path, find any forward
" imports and create a definition metadata dict.
function! pymport#definition(name, basedir, path, lineno, content) abort "{{{
  let module = pymport#module(a:path, a:basedir)
  return {
        \ 'path': a:path,
        \ 'lineno': a:lineno,
        \ 'content': a:content,
        \ 'module': module,
        \ 'forward_module': pymport#forward_module(a:basedir, module, a:name),
        \ }
endfunction "}}}

" invoke the g:pymport_finder to locate definitions of a:name anywhere below
" a:path and create definition dicts.
function! pymport#find_definition(name, path) abort "{{{
  let files = []
  let keywords = '(class|def)'
  let pattern = printf('^(%s %s\(|%s\s*=)', keywords, a:name, a:name)
  if filereadable(a:path) || isdirectory(a:path)
    let output = call(g:pymport_finder, [pattern, a:path])
    for fields in output
      call add(files, call('pymport#definition', [a:name, a:path] + fields))
    endfor
  endif
  return files
endfunction "}}}

" filter the entries in a:locations that refer to the identical module, thus
" resulting in the same import statement.
function! pymport#remove_location_dups(locations) abort "{{{
  function! Uniq(locs, index, loc) abort "{{{
    return len(filter(a:locs[a:index + 1:],
          \ 'a:loc.forward_module == v:val.forward_module')) == 0
  endfunction "}}}
  return filter(copy(a:locations), 'Uniq(a:locations, v:key, v:val)')
endfunction "}}}

" aggregate search results from all locations in g:pymport_paths
function! pymport#locations(name) abort "{{{
  let locations = []
  for path in g:pymport_paths
    let locations += pymport#find_definition(a:name, path)
  endfor
  return pymport#remove_location_dups(locations)
endfunction "}}}

" TODO limit line length by by &columns
function! pymport#prompt_format(index, file) abort "{{{
  return '['. (a:index+1) .'] '.a:file['forward_module'] .':'.a:file['lineno']
        \ .'  '.  a:file['content']
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
" to the line (1) or the import block (0) or placed separate (-1).
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

" add the line number and second token, which is the module in both import
" kinds, to a:imports if the import is below max_line (i.e. the first
" class/def)
function! s:add_import(imports, max_line) abort "{{{
  if !a:max_line || line('.') < a:max_line
    call add(a:imports, [line('.'), split(getline('.'))[1]])
  endif
endfunction "}}}

" TODO skip lines with 'as'
" collect all top level import statements and call the matching function.
" imports located below the first unintented class or function definition are
" ignored.
function! pymport#target_location(target, name) abort "{{{
  let imports = []
  normal! 1G
  keepjumps let header_end = search('\v^<(class|def) \w+\(', 'cn')
  normal! ``
  silent global /\%(^from\|import\) / call s:add_import(imports, header_end)
  let @/ = ''
  return pymport#best_match(imports, a:target['forward_module'])
endfunction "}}}

" find the end of a single or multi line import by checking for parentheses
function! pymport#goto_end_of_import(lineno) abort "{{{
  execute a:lineno.' normal! $'
  call searchpair('(', '', ')')
endfunction "}}}

" surround the imported names with parentheses
function! pymport#add_parentheses(lineno) abort "{{{
  execute 'keepjumps' . a:lineno .
        \ ' substitute /import \zs.\{-}\ze\%(\s*#.*\)\?$/(&)'
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

function! pymport#append_import_to_line(name, lineno) abort "{{{
  keepjumps substitute /\()\?\)\ze\%(\s*#.*\)\?$/\=', '.a:name .submatch(1)/
  let @/ = ''
  call call(g:pymport_formatter, [a:lineno, line('.')])
endfunction "}}}

function! pymport#create_import_line(separate, line) abort "{{{
  if a:separate
    put =''
  endif
  put =a:line
endfunction "}}}

" given the line number of the last matching import, either append the name
" to an exactly matching existing import line or create a new import
function! pymport#insert_import(exact, name, lineno, import) abort "{{{
  if a:exact == 1
    call pymport#append_import_to_line(a:name, a:lineno)
  else
    call pymport#create_import_line(a:exact == -1, a:import)
  endif
endfunction "}}}

" TODO skip existing imports
function! pymport#deploy(lineno, exact, target, name) abort "{{{
  let import = 'from '.a:target['forward_module'] .' import '. a:name
  if a:lineno == 0
    0 put =''
    0 put =import
  else
    call pymport#goto_end_of_import(a:lineno)
    call pymport#insert_import(a:exact, a:name, a:lineno, import)
  endif
endfunction "}}}

" determine all candidates and query the user if more than one was found
function! pymport#resolve(name) abort "{{{
  let target = {}
  let files = pymport#locations(a:name)
  if !empty(files)
    let target = pymport#choose(files)
  endif
  return target
endfunction "}}}

" find the appropriate spot for the import and deploy it
function! pymport#process(target, name) abort "{{{
  let [lineno, exact] = call(g:pymport_target_locator, [a:target, a:name])
  return pymport#deploy(lineno, exact, a:target, a:name)
endfunction "}}}

" Save the current view state
" The initial location is remembered in the ` mark and the remaining view
" parameters are queried via winsaveview()
function! pymport#save_view() abort "{{{
  normal! mp
  let b:pymport_saved_view = winsaveview()
endfunction "}}}

" Restore the initial view state
" In case the import insertion created new lines, the ` mark holds the
" correct position, while the line number obtained from winsaveview() isn't
" updated.
" As the whole procedure leaves one entry at that same position on the jump
" stack, a <c-o> keypress is simulated.
function! pymport#restore_view(pop_jump) abort "{{{
  if exists('b:pymport_saved_view')
    call winrestview(b:pymport_saved_view)
    unlet b:pymport_saved_view
  endif
  normal! g`p
  if a:pop_jump
    call feedkeys("\<c-o>")
  endif
endfunction "}}}

" main function
" TODO implement a method to determine where imports should begin (e.g. after
" docstring)
function! pymport#import(name) abort "{{{
  call pymport#save_view()
  let target = pymport#resolve(a:name)
  if !empty(target)
    call pymport#process(target, a:name)
  else
    call pymport#warn('No match for "'.a:name.'"!')
  endif
  call pymport#restore_view(!empty(target))
endfunction "}}}
