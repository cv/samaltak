// Tokenize chunk files, Tonel files, and loose Smalltalk.
const letter = /[\p{L}_]/;
const identifier = seq(letter, /[\p{L}\p{N}\p{M}_]*/);
const quoted = seq("'", repeat(choice(/[^']+/, "''")), optional("'"));

module.exports = grammar({
  name: 'smalltalk',

  extras: $ => [/[\p{White_Space}\uFEFF]/, $.comment],

  rules: {
    source_file: $ => repeat(choice(
      $._literal, $.identifier, $.keyword, $.operator,
      $.assignment, $.return, $.punctuation, $.bang,
    )),

    _literal: $ => choice(
      $.string, $.character, $.symbol, $.number,
      $.literal_array, $.byte_array,
    ),

    comment: _ => token(/"[^"]*"?/),
    string: _ => token(quoted),
    character: _ => token(seq('$', /[\s\S]/)),
    symbol: _ => token(seq(/#+/, choice(
      quoted, seq(letter, /[\p{L}\p{N}\p{M}_:]*/), /[+*\/\\<>=~@%&?,!|\-\p{Sm}]+/,
    ))),
    number: _ => token(/-?[0-9]+(r-?[0-9A-Za-z]+(\.[0-9A-Za-z]+)?|(\.[0-9]+)?([edq][+-]?[0-9]+)?(s[0-9]*)?)/),

    literal_array: $ => seq('#(', repeat($._array_element), ')'),
    _nested_array: $ => seq('(', repeat($._array_element), ')'),
    _array_element: $ => choice(
      $._literal, $._nested_array, alias($.identifier, $.bare_symbol),
      alias($.keyword, $.bare_symbol), alias($.operator, $.bare_symbol),
      alias('|', $.bare_symbol),
    ),
    byte_array: $ => seq('#[', repeat($.number), ']'),

    identifier: _ => token(identifier),
    keyword: $ => seq($.identifier, token.immediate(':')),
    operator: _ => token(/[+*\/\\<>=~@%&?,\-\p{Sm}]+/),
    assignment: _ => ':=',
    return: _ => '^',
    bang: _ => choice('!', '!!'),
    punctuation: _ => choice('(', ')', '[', ']', '{', '}', '.', ';', ':', '|'),
  },
});
