command! -buffer PymportCWord call pymport#import(expand('<cword>'))

nmap <buffer><silent> <Plug>(pymport_cword) :PymportCWord<cr>
