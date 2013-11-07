const SELECTOR_TIMEOUT = 20 * 1000;
const LOGIN_TIMEOUT = 10 * 1000;

const TEST_URL = 'http://www.apple.com/library/test/success.html';
const EXPECTED_RESULT = 'Success';

var casper = require('casper').create();
var casper2 = require('casper').create();
casper2.start('about:blank');

var args = casper.cli.args;
var FORMS = require(args[0]).forms;
var SSID = args[1];
var BSSID = args[2];

function timeout() {
	casper.echo('Failed to find login form, timed out.');
	casper.exit(1);
}

function connected(casper) {
	var resultBody = casper.fetchText('body').trim();

	//casper.echo('>' + resultBody + '<');

	return resultBody === EXPECTED_RESULT;
}

function checkConnection() {
	casper2.thenOpen(TEST_URL, function() {
		if(connected(casper2)) {
			casper.echo('Successfully logged in.');
			casper.exit(0);
		} else {
			setTimeout(checkConnection, 500);
		}
	});
}

casper.start(TEST_URL, function() {
	if(connected(casper)) {
		casper.echo('Already logged in.');
		casper.exit(0);
	}

	var URL = casper.getCurrentUrl();

	if(URL === 'about:blank') {
		casper.echo('Redirected to about:blank, are you connected to the network?');
		casper.exit(1);
	}

	var form;
	var matches;
	for(var i = 0; i < FORMS.length; i++) {
		form = FORMS[i];
		var match = form.match;

		matches = true;

		for(var key in match) {
			if(match.hasOwnProperty(key)) {
				var value = match[key];
				if(!(value instanceof Array)) {
					value = [value];
				}
				switch(key) {
					case 'SSID':
						if(value.indexOf(SSID) !== -1) {
							continue;
						}
						break;
					case 'BSSID':
						if(value.indexOf(BSSID) !== -1) {
							continue;
						}
						break;
					case 'URL':
						if(value.indexOf(URL) !== -1) {
							continue;
						}
						break;
				}

				matches = false;
				break;
			}
		}

		if(matches) {
			break;
		}
	}

	if(!matches) {
		casper.echo('No login details found for:');
		casper.echo('SSID = ' + SSID);
		casper.echo('BSSID = ' + BSSID);
		casper.echo('URL = ' + URL);
		casper.exit(1);
	}

	var form_selector = form['form_selector'] || 'form';
	var form_fields = form['fields'];

	var selectors = [form_selector];

	for(var key in form_fields) {
		if(form_fields.hasOwnProperty(key)) {
			selectors.push('[name="' + key + '"]');
		}
	}
			 
	casper.echo(selectors);

	for(var i = 0; i < selectors.length; i++) {
		casper.waitForSelector(selectors[i], null, timeout, SELECTOR_TIMEOUT);
	}

	casper.then(function() { // All selectors exists, login now
		casper.fill(form_selector, form_fields, true);

		casper.then(function() {
			casper.wait(LOGIN_TIMEOUT, function() { // Timeout for trying to check connection
				casper.echo('Failed to login, timed out.');
				casper.exit(1);
			});

			casper2.run(); // Stops casper2 from quitting the whole script before it is needed
			checkConnection(); // Use casper2 to keep the login page open just in case it wasn't loaded completely by now
		});
	});
});

casper.run();
