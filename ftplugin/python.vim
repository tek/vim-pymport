command! -buffer -bang PymportCWord
      \ call pymport#import(expand('<cword>'), '<bang>')

nmap <buffer><silent> <Plug>(pymport_cword) :PymportCWord<cr>
