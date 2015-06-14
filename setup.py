# -*- coding: utf-8 -*-

import os
from setuptools import setup


def read(fname):
    return open(os.path.join(os.path.dirname(__file__), fname)).read()

setup(
    name="crudini",
    version="0.7",
    author="Pádraig Brady",
    author_email="P@draigBrady.com",
    description=("A utility for manipulating ini files"),
    license="GPLv2",
    keywords="ini config edit",
    url="http://github.com/pixelb/crudini",
    long_description=read('README'),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Topic :: Utilities",
        "Topic :: System :: Systems Administration",
        "License :: OSI Approved :: GNU General Public License v2 (GPLv2)",
        "Programming Language :: Python :: 2",
    ],
    install_requires=['iniparse'],
    scripts=["crudini"]
)
