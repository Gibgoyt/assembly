In C, `stack_demo.asm` will look something like this
```c
long square_plus (
    long a,
    long b
) {
    long s = a*a;
    long t = s + b;

    return t;
}

long outer (
    long x
) {
    long r = square_plus(x, 5);

    return r + x;
}
```

`_start` push pop demo, then exit(outer(3))
```
