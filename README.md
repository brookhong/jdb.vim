## A JDB plugin for VIM

With the plugin, you could set breakpoint in some Java file with VIM, attach some running Java process with JDWP enabled, then step through your code.

> The plugin depends on `channel` feature from VIM 8.0, so to use this plugin, you must have VIM over 8.0.

## Steps to use

1. Launch your java program with JDWP enabled, such as

    >java -Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=y,address=6789 Sample

    >MAVEN_OPTS="-Xdebug -Xrunjdwp:transport=dt_socket,server=y,address=6789,server=y,suspend=n" mvn spring-boot:run

1. Open your java source file with VIM

1. `<F10>` to set breakpoint at current line

1. `<F5>` to attach the running process, if you're using different port, change it with below command

    >let g:jdbPort="6799"

1. `<F3>` to step through your code now.

### Debugging keys
* `<F2>` to step into.
* `<F4>` to step out.
* `<F5>` to continue.
* `<F6>` to quit.
* Visual select a word or expression, then `E` to print its value or eval it.
