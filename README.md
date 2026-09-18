# Slurm + Pyxis Builder

为 Ubuntu 22.04、Ubuntu 24.04、Debian 12 和 Debian 13 构建对应的
Slurm DEB 软件包和 Pyxis `spank_pyxis.so` 插件。

## 使用方法

只使用一个构建入口。默认构建 Slurm 26.05.4 和 Pyxis 0.24.0：

```bash
./scripts/build.sh \
  --target ubuntu22
```

需要构建其他版本时仍可临时覆盖：

```bash
./scripts/build.sh \
  --target ubuntu22 \
  --slurm-version 25.05.9 \
  --pyxis-version 0.24.0
```

`--target` 支持：

```text
ubuntu22
ubuntu24
debian12
debian13
all
```

缺少对应源码时，脚本会自动下载；已有源码会直接复用。构建完成后会自动
校验软件包和 SHA256。

Pyxis 不打包成 DEB，输出目录中只生成：

```text
spank_pyxis.so
```

## 输出目录

```text
output/
└── slurm-26.05.4_pyxis-0.24.0/
    ├── ubuntu22.04/
    ├── ubuntu24.04/
    ├── debian12/
    └── debian13/
```

重复构建同一版本时，已有目标目录会保存为带时间戳的备份。

## 构建其他系统

```bash
./scripts/build.sh \
  --target ubuntu24
```

```bash
./scripts/build.sh \
  --target debian12
```

```bash
./scripts/build.sh \
  --target debian13
```

一次构建全部三个系统：

```bash
./scripts/build.sh \
  --target all
```

四种系统的 DEB 包不能交叉安装。Slurm 版本必须与集群主节点保持一致，
Pyxis 会使用同一次构建产生的 Slurm 开发包进行编译。

部署 Pyxis 时，将 `spank_pyxis.so` 放到计算节点的 Slurm 插件目录，并在
`plugstack.conf` 中使用实际绝对路径加载。例如：

```text
required /usr/local/lib/slurm/spank_pyxis.so
```

Pyxis 运行时仍然要求计算节点已经安装并配置 Enroot。
