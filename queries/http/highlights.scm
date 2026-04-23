; Requires nvim-treesitter + :TSInstall http

(method) @keyword
(url) @string
(header name: (field_name) @property)
(header value: (field_value) @string)
(variable name: (_) @special)
(number) @number
(boolean) @boolean
(null_literal) @constant.builtin
(comment) @comment
(section_separator) @punctuation.special
