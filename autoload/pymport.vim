function! pymport#warn(msg) "{{{
  echohl WarningMsg
  echo 'pymport: '.a:msg
  echohl None
endfunction "}}}

function! pymport#normalize_path(path) "{{{
  let path = fnamemodify(a:path, ':p')
  if path[-1:] == '/'
    let path = path[:-2]
  endif
  return path
endfunction "}}}

function! pymport#module(path, basedir) "{{{
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

function! pymport#greplike(cmdline, name, path) "{{{
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

function! pymport#grep(name, path) "{{{
  return pymport#greplike("grep -n -E -r --include='*.py' '%s %s\\(' %s", a:name, a:path)
endfunction "}}}

function! pymport#ag(name, path) "{{{
  return pymport#greplike('ag -G "\.py$" "%s %s\(" %s', a:name, a:path)
endfunction "}}}

function! pymport#locations(name) "{{{
  let locations = []
  for path in g:pymport_paths
    let locations += call(g:pymport_finder, [a:name, path])
  endfor
  return locations
endfunction "}}}

function! pymport#prompt_format(index, file) "{{{
  return '['. (a:index+1) .'] '.a:file['module'] .':'.a:file['lineno'] .'  '.
        \ a:file['content']
endfunction "}}}

function! pymport#prompt(files) "{{{
  let lines = ['Multiple matches:'] +
        \ map(copy(a:files), 'pymport#prompt_format(v:key, v:val)')
  let choice = inputlist(lines)
  return choice ? a:files[choice-1] : []
endfunction "}}}

function! pymport#choose(files) "{{{
  return len(a:files) > 1 ? pymport#prompt(a:files) : a:files[0]
endfunction "}}}

function! pymport#package(module) "{{{
  return split(a:module, '\.')[0]  
endfunction "}}}

function! pymport#best_match(imports, module) "{{{
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
  return best
endfunction "}}}

" TODO skip lines with 'as'
function! pymport#target_location(target, name) "{{{
  let module = a:target['module']
  let imports = []
  function! Adder(imports) "{{{
    call add(a:imports, [line('.'), split(getline('.'))[1]])
  endfunction "}}}
  silent global /\%(^from\|import\) / call Adder(imports)
  let @/ = ''
  return pymport#best_match(imports, module)
endfunction "}}}

function! pymport#goto_end_of_import(lineno) "{{{
  execute a:lineno.'normal! $'
  call searchpair('(', '', ')')
endfunction "}}}

function! pymport#add_parentheses(lineno) "{{{
  execute a:lineno .'substitute /import \zs.*/(&)'
  let @/ = ''
endfunction "}}}

function! pymport#format(lineno) "{{{
  execute a:lineno.',. join'
  if len(getline(a:lineno)) > &textwidth
    call pymport#add_parentheses(a:lineno)
    execute a:lineno 'normal! gqq'
  endif
endfunction "}}}

" TODO skip existing imports
function! pymport#deploy(lineno, exact, target, name) "{{{
  let import = 'from '.a:target['module'] .' import '. a:name
  if a:lineno == 0
    0 put =''
    0 put =import
  else
    call pymport#goto_end_of_import(a:lineno)
    if a:exact == 1
      substitute /\()\?\)$/\=', '.a:name .submatch(1)/
      let @/ = ''
      call call(g:pymport_formatter, [a:lineno])
    else
      if a:exact == -1
        put =''
      endif
      put =import
    endif
  endif
endfunction "}}}

function! pymport#process(name, files) "{{{
  let target = pymport#choose(a:files)
  if len(target) > 0
    let [lineno, exact] = pymport#target_location(target, a:name)
    call pymport#deploy(lineno, exact, target, a:name)
  endif
endfunction "}}}

function! pymport#import(name) "{{{
  let files = pymport#locations(a:name)
  if len(files) > 0
    call pymport#process(a:name, files)
  else
    call pymport#warn('No match for "'.a:name.'"!')
  endif
endfunction "}}}

if(!exists('*'.g:pymport_finder))
  let g:pymport_finder = 'pymport#ag'
endif

if(!exists('*'.g:pymport_formatter))
  let g:pymport_formatter = 'pymport#format'
endif
