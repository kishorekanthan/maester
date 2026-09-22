## Idle CPU

Method: built and installed the app (`./build.sh`), launched it
(`open -a ~/Applications/Maester.app`) with the default providers (`apps`,
`mac`) enabled and streaming, let it settle for 5 seconds, then sampled its
`%CPU` once per second for 60 seconds with:

```
top -l 61 -s 1 -pid <maester-pid> -stats pid,cpu
```

Result, on an Apple Silicon Mac (macOS 15/26 series), 61 samples:

| | value |
|---|---|
| average | 0.013% |
| max | 0.4% |
| samples over 1% | 0 |

Idle self-cost is well under the 1% CPU target.
