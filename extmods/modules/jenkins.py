import urllib
import requests

from xml.dom.minidom import parseString


class WithCrumb(object):

    def __init__(self, url, user, pw):
        self.url = url
        self.user = user
        self.pw = pw
        self.crumb = None
        self.session = requests.Session()

    def requestCrumb(self):
        if not self.crumb:
            crumbUrl = urllib.parse.urljoin(self.url, 'crumbIssuer/api/xml/?xpath=concat(//crumbRequestField,":",//crumb)')
            r = self.session.get(crumbUrl, auth=(self.user, self.pw))
            assert r.status_code == 200, (r.status_code, r.text)
            c = r.text.split(":")
            self.crumb = {c[0]: c[1]}

    def request(self, method, url_fragment, **parms):
        self.requestCrumb()
        url = urllib.parse.urljoin(self.url, url_fragment)
        if "headers" in parms:
            parms["headers"].update(self.crumb)
        else:
            parms["headers"] = self.crumb.copy()
        f = self.session.post if method == "POST" else self.session.get
        r = f(url, auth=(self.user, self.pw), **parms)
        assert r.status_code == 200, (r.status_code, r.text)
        return r.text

    def get(self, url_fragment, *args, **kwargs):
        return self.request(url_fragment=url_fragment, method="GET", *args, **kwargs)

    def post(self, url_fragment, *args, **kwargs):
        return self.request(url_fragment=url_fragment, method="POST", *args, **kwargs)


def groovy(name, code, jenkins_url, username, password):
    ret = {
        'name': name,
        'changes': {},
        'result': False,
        'comment': ''
    }
    requestor = WithCrumb(jenkins_url, username, password)
    data = urllib.parse.urlencode({'script': code})
    response = requestor.post("scriptText", data=data, headers={"Content-Type": "application/x-www-form-urlencoded", "Accept": "text/plain"})
    return response


def existing_plugins_and_versions(jenkins_url, username, password):
    requestor = WithCrumb(jenkins_url, username, password)
    response = requestor.get("pluginManager/api/xml?depth=1&xpath=/*/*/shortName|/*/*/version&wrapper=plugins")
    parsed = parseString(response)
    shortnames = parsed.getElementsByTagName("shortName")
    versions = parsed.getElementsByTagName("version")
    plugin_names_and_versions = dict()
    for n, v in zip(shortnames, versions):
        n = "".join(c.nodeValue for c in n.childNodes)
        v = "".join(c.nodeValue for c in v.childNodes)
        plugin_names_and_versions[n] = v
    return plugin_names_and_versions

def install_plugins(plugins, jenkins_url, username, password):
    shell = '<jenkins>%s</jenkins>'
    plugreq = '<install plugin="%s@latest" />'
    p = "".join([plugreq % t for t in plugins])
    text = shell % p
    requestor = WithCrumb(jenkins_url, username, password)
    text = requestor.post('pluginManager/installNecessaryPlugins', data=text, headers={"Content-Type": "text/xml"})
    return text
