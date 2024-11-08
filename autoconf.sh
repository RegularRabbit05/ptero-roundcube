#!/bin/bash

socat TCP-LISTEN:50004,fork TCP:127.0.0.1:81 &
