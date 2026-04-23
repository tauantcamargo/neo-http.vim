if exists("b:current_syntax")
  finish
endif

syntax case match

" Block separator (### optional name)
syntax match httpSeparator    /^###.*$/        contains=httpSeparatorName
syntax match httpSeparatorName /###\s*\zs.*$/  contained

" Comments (single # lines, not ###)
syntax match httpComment      /^#[^#].*$/
syntax match httpComment      /^#$/

" @directive lines
syntax match httpDirective    /^@[a-zA-Z_][a-zA-Z0-9_\-]*\s*=.*$/ contains=httpDirectiveKey,httpDirectiveVal
syntax match httpDirectiveKey /^@[a-zA-Z_][a-zA-Z0-9_\-]*/        contained
syntax match httpDirectiveVal /=\s*\zs.*$/                          contained

" Method + URL line
syntax match httpMethod /^\(GET\|POST\|PUT\|DELETE\|PATCH\|HEAD\|OPTIONS\|TRACE\|CONNECT\|WS\|WSS\)\ze\s/
syntax match httpUrl    /\(GET\|POST\|PUT\|DELETE\|PATCH\|HEAD\|OPTIONS\|TRACE\|CONNECT\|WS\|WSS\)\s\+\zs\S\+/

" Headers
syntax match httpHeaderName /^[A-Za-z][A-Za-z0-9\-]*\ze:/
syntax match httpHeaderColon /^[A-Za-z][A-Za-z0-9\-]*\zs:/

" Variables {{name}} and dynamic {{$name}}
syntax match httpVariable /{{[^$}][^}]*}}/
syntax match httpDynVar   /{{$[^}]*}}/

" Query continuation lines
syntax match httpQueryParam /^\s\+[?&][^ ]*/

" Numbers in body
syntax match httpNumber /\b\d\+\(\.\d\+\)\?\b/

" Booleans / null in body
syntax keyword httpLiteral true false null

highlight default link httpSeparator    Special
highlight default link httpSeparatorName Title
highlight default link httpComment      Comment
highlight default link httpDirective    PreProc
highlight default link httpDirectiveKey PreProc
highlight default link httpDirectiveVal String
highlight default link httpMethod       Keyword
highlight default link httpUrl          String
highlight default link httpHeaderName   Identifier
highlight default link httpHeaderColon  Delimiter
highlight default link httpVariable     Special
highlight default link httpDynVar       Macro
highlight default link httpQueryParam   String
highlight default link httpNumber       Number
highlight default link httpLiteral      Boolean

let b:current_syntax = "http"
