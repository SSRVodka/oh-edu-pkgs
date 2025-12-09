#!/bin/bash

for i in {1..8}; do
    arg="${!i}"
    if [ -n "$arg" ]; then
        echo "param $i: $arg"
    else
        echo "param $i: (empty)"
    fi
done

