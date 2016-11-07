# StatsD Erlang client

This is a heavy-rewrite fork of upstream [statsderl](https://github.com/lpgauth/statsderl), base version: 0.4.7.

Changes:

* Renamed project from statsderl to `statsd_erlang` (API modules names are not changed)
* Removed pooling
* Allow starting worker linked to caller (under any supervision tree)
* Added batch report API for callers
* Added timeout based buffer for UDP packets batching

## Examples

Start metrics reporter under `statad_erlang`'s supervisor

```erlang
> application:load(statsd_erlang).
> application:set_env(statsd_erlang, hostname, "localhost").
> application:ensure_all_started(statsd_erlang).
> statsderl:increment(["test", $., "counter"], 1, 0.23).
> statsderl:gauge([<<"test">>, $., "gauge"], 333, 1.0).
> statsderl:timing("test.timing", 5, 0.999).
```

Start metrics reporter on demand with an optional pid registration name.

```erlang
> {ok, Pid} = statsderl:start_link([{hostname, "localhost"}, {name, thename}]).
> statsderl:increment(Pid, ["test", $., "counter"], 1, 0.9).
> statsderl:gauge(Pid, [<<"test">>, $., "gauge"], 333, 1.0).
> statsderl:timing(thename, "test.timing", 5, 0.999).
```

## License

```license
The MIT License (MIT)

Copyright (c) 2011-2016 Louis-Philippe Gauthier

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
