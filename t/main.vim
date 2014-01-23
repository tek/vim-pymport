describe 'pymport'

  it 'finds a function'
    let g:pymport_paths = [getcwd().'/t/data/foo']
    let g:pymport_finder = 'pymport#ag'
    let ret = pymport#locations('foobar')
    Expect ret[1]['content'] != ret[0]['content']
    Expect ret[0]['module'] == 'bar.stuff'
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

describe 'locate and deploy'

  before
    edit ./t/data/target_location.py
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
    Expect lineno == 6
    Expect exact == 0
    let g:target['module'] = 'thirdparty.stuff'
    let [lineno, exact] = pymport#target_location(g:target, g:name)
    Expect lineno == 5
    Expect exact == 1
    let g:target['module'] = 'unmatched.stuff'
    let [lineno, exact] = pymport#target_location(g:target, g:name)
    Expect lineno == 8
    Expect exact == -1
  end

  it 'appends an import statement'
    call pymport#deploy(8, -1, g:target, g:name)
    Expect getline('10') == 'from '.g:target['module'].' import '.g:name
  end

  it 'inserts an import statement'
    call pymport#deploy(6, 0, g:target, g:name)
    Expect getline('7') == 'from '.g:target['module'].' import '.g:name
  end

  it 'appends a name to an existing import statement'
    let g:target['module'] = 'thirdparty.fluff'
    call pymport#deploy(6, 1, g:target, g:name)
    Expect getline('6') == 'from '.g:target['module'].' import Fluff, '.g:name
  end
end
