# Foreign function interface

`FFI bind:` takes a descriptor: an array that names an approved native export and
its exact signature. The returned binding sends arguments to the export through a
generated adapter. A descriptor can be a literal or an array assembled at runtime;
both go through the same checks.

```smalltalk
(FFI bind: #(call 'libm' 'sqrt' (f64) f64)) invoke: #(9.0)
"3.0"
```

The image does not get native addresses. Calls may borrow bounded bytes for the
duration of the call where the export allows it; native code must not retain the
borrow or reenter the image. Launcher grants authorize named signatures, not
whole libraries, and are checked again at invocation, including after restoring
a snapshot.
