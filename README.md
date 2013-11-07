NetworkAutoLogin
================

Automagically logs into to Captive Portal Networks

Installation
------------

- Download phantomjs from http://phantomjs.org/download.html and copy `bin/phantomjs` to `NetworkAutoLogin/resources`.
- Download casperjs from https://github.com/n1k0/casperjs/releases and copy the contents of the directory to `NetworkAutoLogin/resources/casperjs`
- Open the project with Xcode and build the "Install" target
- Edit `~/.networkautologin.js`

Configuration format
--------------------
The format to use in `~/.networkautologin.js` is a javascript file with definition for `exports.forms`, which should be an array of objects.

Each of these objects should contain a `matches` & a `fields` key and optionally a `form_selector` key.

The `matches` key should contain an object with one or more of the following keys: `SSID`, `BSSID`, `URL`. Each of these fields should contain either be a string or an array of strings to be matched. The `URL` key, if present, should specify the URL redirected to when requesting `http://www.apple.com/library/test/success.html` from the unauthenticated network.

The `fields` key should contain an object with keys specifying HTML form element names and the values representing the values of those fields to be filled in.

The `form_selector` key can be used if multiple forms are present on the page. If this field is not present, it will default to just `form`, matching the first form on the page.

Example configuration
---------------------
```
exports.forms = [
    { // Example with all possible options
		match: {
			SSID: ['Example WiFi 1', 'Example WiFi 2'],
			BSSID: '01:23:45:67:89:AB',
			URL: 'http://logon.example.org/?url=http://www.apple.com/library/test/success.html'
		},
		form_selector: 'form#login_form',
		fields: {
			'username': 'test',
			'password': '123123'
		}
	}
];
```

This example will run when connected to a network with either the SSID of `Example WiFi 1` or `Example WiFi 2`, with the BSSID of `01:23:45:67:89:AB` and which redirects to `http://logon.example.org/?url=http://www.apple.com/library/test/success.html` when requesting `http://www.apple.com/library/test/success.html`.

When this happens the script will find the form matching the CSS selector `form#login_form` and fill the input with the name `username` with `test` and the input with the name `password` with `123123`.

Finally it will submit the form and check that it is successfully connected the Internet.

A barebones example can be seen below:
```
exports.forms = [
    { // Minimal example
		match: {
			SSID: 'Example WiFi'
		},
		fields: {
			'username': 'test',
			'password': '123123'
		}
	},
];
```
