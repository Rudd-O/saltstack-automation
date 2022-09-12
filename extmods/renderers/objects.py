"""
Python renderer that includes a Pythonic object-based DSL.

This is strongly based on the pyobjects renderer, but removes the limitations
on state modules being only the built-in ones.  For a name to be recognized
as a state module, it must start with an uppercase letter.

:maintainer: Manuel Amador (Rudd-O) <rudd-o@rudd-o.com>

Refer to the SaltStack pyobjects documentation for usage instructions.
"""

import collections
import logging
import os
import re

import salt.loader
import salt.utils.files
from salt.fileclient import get_file_client
from salt.utils.pyobjects import Map, Registry, SaltObject, StateFactory

# our import regexes
FROM_RE = re.compile(r"^\s*from\s+(salt:\/\/.*)\s+import (.*)$")
IMPORT_RE = re.compile(r"^\s*import\s+(salt:\/\/.*)$")
FROM_AS_RE = re.compile(r"^(.*) as (.*)$")

log = logging.getLogger(__name__)

try:
    __context__["objects_loaded"] = True
except NameError:
    __context__ = {}


class PyobjectsModule:
    """This provides a wrapper for bare imports."""

    def __init__(self, name, attrs):
        self.name = name
        self.__dict__ = attrs

    def __repr__(self):
        return "<module '{!s}' (objects)>".format(self.name)


def uncamelcase(s):
    news = []
    for n, c in enumerate(s):
        if re.match("[A-Z]", c):
            if n > 0:
                news += "_"
            news += c.lower()
        else:
            news += c
    return "".join(news)


class DefaultStateFactoryDict(dict):
    """
    This magic dictionary will create a StateFactory for any lookups
    of objects not present in the dictionary.  The StateFactory that
    gets instantiated in that case gets an un-camel-cased version
    of the name of the key.  Thus:

        PostgresDatabase -> StateFactory("postgres_database")
    """

    def __getitem__(self, key):
        if key in self:
            return dict.__getitem__(self, key)
        if key[0].lower() == key[0]:
            # Uh oh, this is not valid.  Must be uppercase!
            raise NameError(key)
        dict.__setitem__(self, key, StateFactory(uncamelcase(key)))
        return dict.__getitem__(self, key)


def prep_globals(sls):
    _globals = DefaultStateFactoryDict()

    # add all builtins
    for k in __builtins__:
        if (
            k
            in [
                "copyright",
                "credits",
                "compile",
                "eval",
                "exec",
                "exit",
                "help",
                "input",
                "license",
                "open",
                "quit",
            ]
            or k.startswith("_")
        ):
            continue
        _globals[k] = __builtins__[k]
    _globals["__file__"] = sls

    # add our include and extend functions
    _globals["include"] = Registry.include
    _globals["extend"] = Registry.make_extend

    # Salt object for Salt.state.
    _globals["Salt"] = StateFactory("salt")
    _globals["Test"] = StateFactory("test")
    _globals["SLS"] = StateFactory("sls")

    # add the name of the SLS (not available in pyobjects, but
    # available in the Jinja renderer)
    _globals["sls"] = sls

    # add our map class
    Map.__salt__ = __salt__
    _globals["Map"] = Map

    # add some convenience methods to the global scope as well as the "dunder"
    # format of all of the salt objects
    try:
        _globals.update(
            {
                # Magical SLS dependency object.
                # salt, pillar & grains all provide shortcuts or object interfaces
                "salt": SaltObject(__salt__),
                "pillar": __salt__["pillar.get"],
                "grains": __salt__["grains.get"],
                "mine": __salt__["mine.get"],
                "config": __salt__["config.get"],
                # the "dunder" formats are still available for direct use
                "__salt__": __salt__,
                "__pillar__": __pillar__,
                "__grains__": __grains__,
            }
        )
    except NameError:
        pass

    return _globals


def render(template, saltenv="base", sls="", salt_data=True, **kwargs):
    # these hold the scope that our sls file will be executed with
    _globals = prep_globals(sls)

    # if salt_data is not True then we just return the global scope we've
    # built instead of returning salt data from the registry
    if not salt_data:
        return _globals

    # this will be used to fetch any import files
    client = get_file_client(__opts__)

    # process our sls imports
    #
    # we allow pyobjects users to use a special form of the import statement
    # so that they may bring in objects from other files. while we do this we
    # disable the registry since all we're looking for here is python objects,
    # not salt state data
    Registry.enabled = False

    def process_template(template):
        template_data = []
        # Do not pass our globals to the modules we are including and keep the root _globals untouched
        template_globals = prep_globals(sls)
        for line in template.readlines():
            line = line.rstrip("\r\n")
            matched = False
            for RE in (IMPORT_RE, FROM_RE):
                matches = RE.match(line)
                if not matches:
                    continue

                import_file = matches.group(1).strip()
                try:
                    imports = matches.group(2).split(",")
                except IndexError:
                    # if we don't have a third group in the matches object it means
                    # that we're importing everything
                    imports = None

                state_file = client.cache_file(import_file, saltenv)
                if not state_file:
                    raise ImportError(
                        "Could not find the file '{}'".format(import_file)
                    )

                with salt.utils.files.fopen(state_file) as state_fh:
                    state_contents, state_globals = process_template(state_fh)
                exec(state_contents, state_globals)

                # if no imports have been specified then we are being imported as: import salt://foo.sls
                # so we want to stick all of the locals from our state file into the template globals
                # under the name of the module -> i.e. foo.MapClass
                if imports is None:
                    import_name = os.path.splitext(os.path.basename(state_file))[0]
                    template_globals[import_name] = PyobjectsModule(
                        import_name, state_globals
                    )
                else:
                    for name in imports:
                        name = alias = name.strip()

                        matches = FROM_AS_RE.match(name)
                        if matches is not None:
                            name = matches.group(1).strip()
                            alias = matches.group(2).strip()

                        if name not in state_globals:
                            raise ImportError(
                                "'{}' was not found in '{}'".format(name, import_file)
                            )
                        template_globals[alias] = state_globals[name]

                matched = True
                break

            if not matched:
                template_data.append(line)
            else:
                template_data.append("# processed: " + line)

        return "\n".join(template_data), template_globals

    # process the template that triggered the render
    final_template, final_globals = process_template(template)
    _globals.update(final_globals)

    # re-enable the registry
    Registry.enabled = True

    # now exec our template using our created DSL.
    exec(final_template, _globals)

    return Registry.salt_data()
