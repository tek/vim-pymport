[![Build Status](https://travis-ci.org/tek/vim-pymport.png)](https://travis-ci.org/tek/vim-pymport)

## Description

**pymport** searches desired directories for the definition of a given python
function, class or variable and adds or manipulates an import at the proper
location.

## Usage

For importing `<cword>`, use `<Plug>(pymport_cword)` or `:PymportCWord`.

For an arbitrary identifier, `call pymport#import('name')`.

## Customization

`pymport_paths` A list of directories to be searched

`pymport_finder` The name of a vim function used for searching

`pymport_formatter` The name of a vim function used for final formatting of the import lines

`pymport_target_locator` The name of a vim function used to determine the line where the import should be placed

`pymport_package_precedence` A list of package names that determines the order in which import blocks from these are placed below any other packages

If you want to search third-party packages, you could add a line like this to your config:

`let g:pymport_paths += glob('$VIRTUAL_ENV/lib/python*/site-packages', 0, 1)`

## License

Copyright (c) Torsten Schmits. Distributed under the terms of the [MIT
License][1].

[1]: http://opensource.org/licenses/MIT 'mit license'
