#!/usr/bin/env bash

read -r -p "enter search: " SEARCH

ls -la | rg -i -- "${SEARCH}"
