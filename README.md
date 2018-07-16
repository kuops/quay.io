# sync quay.io 镜像

**build stats:**  [![Build Status](https://travis-ci.org/kuops/quay.io.svg?branch=master)](https://travis-ci.org/kuops/quay.io)

使用 travis cli 对多个文件进行加密

```
tar zcf conf.tar.gz  config.json id_rsa
travis encrypt-file $HOME/conf.tar.gz --add
```

本仓库是 quay.io  仓库中 `coreos`,`calico`,`prometheus` namespace 下的所有镜像，用法如下

```
#原拉取地址
docker pull quay.io/coreos/flannel:v0.10.0-amd64:3.0
#替换 `quay.io/coreos` 为 `kuopsquay/coreos.`
docker pull kuopsquay/coreos.flannel:v0.10.0-amd64
```

