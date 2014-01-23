[![Build Status](https://travis-ci.org/tek/vim-pymport.png)](https://travis-ci.org/tek/vim-pymport)

## Description

**pymport** searches desired directories for the definition of a given python function or class and adds or manipulates an import at the proper location.

## Usage

For importing `<cword>`, use `<Plug>(pymport_cword)` or `:PymportCWord`.

For an arbitrary identifier, `call pymport#import('name')`.

## Customization

`pymport_paths` A list of directories to be searched
`pymport_finder` The name of a vim function used for searching
`pymport_formatter` The name of a vim function used for final formatting of the
import lines

## License

Copyright (c) Torsten Schmits. Distributed under the terms of the [MIT
License][1].

[1]: http://opensource.org/licenses/MIT 'mit license'
