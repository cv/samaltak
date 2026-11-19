(comment) @comment
(string) @string
(character) @string.special
(number) @number
(symbol) @string.special.symbol

((source_file (identifier) @variable.special)
 (#any-of? @variable.special "self" "super" "thisContext"))
((source_file (identifier) @type)
 (#match? @type "^[\\p{Lu}\\p{Lt}]"))

([(source_file (identifier) @boolean) (bare_symbol) @boolean]
 (#any-of? @boolean "true" "false"))
([(source_file (identifier) @constant.builtin) (bare_symbol) @constant.builtin]
 (#eq? @constant.builtin "nil"))
((bare_symbol) @string.special.symbol
 (#not-any-of? @string.special.symbol "true" "false" "nil"))

(keyword) @function.method
[(operator) (assignment)] @operator
(return) @keyword
[(bang) "." ";" ":" "|"] @punctuation.delimiter
["#(" "#[" "(" ")" "[" "]" "{" "}"] @punctuation.bracket
