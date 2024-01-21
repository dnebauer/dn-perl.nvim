# dn-perl #

A filetype plugin that supplies auxiliary perl support

## Dependencies ##

This ftplugin relies on functions provided by the dn-utils plugin. In fact, the
functions provided by this ftplugin will fail if they cannot detect dn-utils.

## K help ##

The K help configured by the vim option

```vim
'keywordprg'
```

defaults in perl file types to search function help:

```sh
perldoc -f X
```

where `X` is the keyword to search for help on.

This plugin sets the option so that K help searches for help on the keyword
sequentially in functions, variables, general, and faq help until it finds a
match:

```sh
perldoc -f X || perldoc -v X || perldoc X || perldoc -q X
```

## Perlcritic ##

Run the perlcritic script provided by the Perl::Critic module to display any
policy violations. See the `perlcritic` man page for further details. The
script can be run using the `:Critic X` command, where `X` is the severity
level (1--5), `<Leader>cX` mappings, where `X` is the severity level (1--5), or
the `dn_perl.critic()` function.

## License ##

This plugin is made available under the GPL3+ license.
