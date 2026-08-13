-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

Format: 3.0 (quilt)
Source: v4l2loopback
Binary: v4l2loopback-source, v4l2loopback-dkms, v4l2loopback-utils
Architecture: any all
Version: 0.15.4-1
Maintainer: IOhannes m zmölnig (Debian/GNU) <umlaeute@debian.org>
Homepage: https://github.com/v4l2loopback/v4l2loopback
Standards-Version: 4.7.4
Vcs-Browser: https://salsa.debian.org/debian/v4l2loopback
Vcs-Git: https://salsa.debian.org/debian/v4l2loopback.git
Testsuite: autopkgtest, autopkgtest-pkg-dkms
Testsuite-Triggers: linux-doc, module-assistant-autopkgtest
Build-Depends: debhelper-compat (= 13), help2man <!cross>
Build-Depends-Indep: dh-sequence-dkms, bzip2
Package-List:
 v4l2loopback-dkms deb kernel optional arch=all
 v4l2loopback-source deb kernel optional arch=all
 v4l2loopback-utils deb graphics optional arch=any
Checksums-Sha1:
 8b75a916050dab03acf9418b2d8734b04d07f561 90032 v4l2loopback_0.15.4.orig.tar.gz
 073049ac1665ef5db9e190fb5abc42e519077fd3 9696 v4l2loopback_0.15.4-1.debian.tar.xz
Checksums-Sha256:
 146801c61aab204b2f1a35c830806f4ee5499f5524814ddd2a8077d367c19aea 90032 v4l2loopback_0.15.4.orig.tar.gz
 cb4a38d701a917add2258fc0401d77571f7c32b85f8bc95a2329e1fff85c0765 9696 v4l2loopback_0.15.4-1.debian.tar.xz
Files:
 e40157a135bd791d2d2b47ed14b54bb0 90032 v4l2loopback_0.15.4.orig.tar.gz
 856f73080ca0cf1262cfb807adbb0bfc 9696 v4l2loopback_0.15.4-1.debian.tar.xz
Dgit: d0044bbe6d60ac0ff68e2e79af49cf6ff0a0dd39 debian archive/debian/0.15.4-1 https://git.dgit.debian.org/v4l2loopback

-----BEGIN PGP SIGNATURE-----

iQIzBAEBCgAdFiEEdAXnRVdICXNIABVttlAZxH96NvgFAmo75TsACgkQtlAZxH96
NviyIg/+PaVDK/eiOPFE2EL1WydhmComB1YdYKtvC3ijKLVBBSg47k2Nak7tH93H
4207Oftd2MBqulARM3To2ULLVn8GdhUqvXOti5q1ufdMkUr1jDaqY0ekZeTd0QoQ
UYhAuIzU1IhIK+8eUj5yGzDkdS/7jMNnZcudh3vuw9M4ToxQEKWsdeEjlSjITWRC
+d4kR9QctNEKSLZNa6mxV7jsdpnAUGqESHNuzQT90zzIqgKZlZJr8afQuN9SkIdN
NYN7oDD4H+po+4Zs8TqWjODGw51YwXz8MC11Iq6vQrmcy6MjPpaFUmHNPJespc2S
QLoqiKRH8fa2WwjjicaazLcFTqbB07GazafqJgEt1/fCeqtTVOlaRXpbt7RIIVKw
ReVQbJRve7+synyzShOHsyApj2Tv5T1IcfjUG7zkkew5r7zLZKV1PaUgzO0pF9Nq
QeIQtUa21fHHjjdGIm3QqxfD4xWcdo1IFwMsneZxuWjJtN7mn9XkxFze+RehEo15
SmWWG2w7FhJglPiVt/TGIuCKQPiM5nv+xmtC6SobpmHNU4DFt4fhdNG634EViBWa
drLlIFWEXdTTYch67A1mHuj8p89dAtUFAEPOU3rUgXqgxIo9OToA2V+Cjf0skWxB
UKsbIINEawfpMxWd+xnLdLPyJGBIk4Ufi6PC0hfRmuo0tNdvJyE=
=xiOq
-----END PGP SIGNATURE-----
