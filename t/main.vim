let g:pymport_paths = [getcwd().'/t/data/foo']
let g:pymport_finder = 'pymport#grep'
let g:pymport_formatter = 'pymport#format'
let g:pymport_target_locator = 'pymport#target_location'

describe 'path resolution:'

  it 'finds a function'
    let ret = pymport#locations('foobar')
    Expect ret[1]['content'] != ret[0]['content']
    Expect ret[0]['module'] =~ 'bar\..*stuff'
  end

  it 'queries the user'
    let files = [
          \ {
          \ 'path': 'foo/bar/zoo',
          \ 'lineno': '4',
          \ 'content': 'class Moo(object)',
          \ 'module': 'foo.bar.zoo',
          \ },
          \ {
          \ 'path': 'zoo/bar/foo',
          \ 'lineno': '73',
          \ 'content': 'def boo()',
          \ 'module': 'zoo.bar.foo',
          \ },
          \ ]
    
    execute "normal! :let answer = pymport#choose(files)\<cr>2\<cr>"
    Expect answer['lineno'] == '73'
  end

  it 'extracts module names'
    let mod = pymport#module('/foo/bar/baz/moo/doo.py', '/foo/bar')
    Expect mod == 'baz.moo.doo'
    let mod = pymport#module('/foo/bar/baz/moo/__init__.py', '/foo/bar')
    Expect mod == 'baz.moo'
  end
end

describe 'locate and deploy:'

  before
    edit ./t/data/target_location.py
    set ft=python
    set textwidth=79
    let g:name = 'Leptospirosis'
    let g:target = {
          \ 'path': 'thirdparty/muff.py',
          \ 'lineno': '4',
          \ 'content': 'class Leptospirosis(object)',
          \ 'module': 'thirdparty.muff',
          \ }
  end

  after
    bdelete!
  end

  it 'finds the target location'
    let [lineno, exact] = pymport#target_location(g:target, g:name)
    Expect lineno == 7
    Expect exact == 0
    let g:target['module'] = 'thirdparty.stuff'
    let [lineno, exact] = pymport#target_location(g:target, g:name)
    Expect lineno == 6
    Expect exact == 1
    let g:target['module'] = 'unmatched.stuff'
    let [lineno, exact] = pymport#target_location(g:target, g:name)
    Expect lineno == 11
    Expect exact == -1
  end

  it 'appends an import statement'
    call pymport#deploy(11, -1, g:target, g:name)
    Expect getline('14') == 'from '.g:target['module'].' import '.g:name
  end

  it 'inserts an import statement'
    call pymport#deploy(7, 0, g:target, g:name)
    Expect getline('8') == 'from '.g:target['module'].' import '.g:name
  end

  it 'appends a name to an existing import statement'
    let g:target['module'] = 'thirdparty.fluff'
    call pymport#deploy(7, 1, g:target, g:name)
    Expect getline('7') == 'from '.g:target['module'].' import Fluff, '.g:name
  end

  it 'appends a name to an existing import statement and exceeds the textwidth'
    let g:target['module'] = 'fourthparty.mudule'
    call pymport#deploy(10, 1, g:target, g:name)
    let part = ' import (LooooooooooooongButNotLongEnough,'
    Expect getline('10') == 'from '.g:target['module'].part
  end

  it 'appends a name to an existing multiline import statement'
    let g:target['module'] = 'fourthparty.sub'
    call pymport#deploy(11, 1, g:target, g:name)
    let part = ' import (LoooooooooooooooooooongAssName, Anoooother,'
    Expect getline('11') == 'from '.g:target['module'].part
    Expect getline('12') =~ '\s*AaaaaaaaandDone, '.g:name.')'
  end

  it 'integration'
    let [bufnum, old_line, old_col, off] = getpos('.')
    call pymport#import('Foobar')
    Expect getline('14') == 'from bar.stuff import Foobar'
    let [bufnum, new_line, new_col, off] = getpos('.')
    Expect [new_line, new_col] == [old_line + 2, old_col]
    " for some esoteric reason, a line break in the output of 'prove', the
    " vim-flavor test runner, is removed by setting the ` mark in
    " pymport#import(), which prevents prove from correctly assessing the
    " test's success.
    " printing something here fixes this.
    echo ' '
  end
end

describe 'empty file:'
  it 'place target in the first line'
    0 put ='foo = 1'
    call pymport#import('Foobar')
    Expect getline('1') == 'from bar.stuff import Foobar'
    Expect getline('3') == 'foo = 1'
  end
end
