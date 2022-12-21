# 🌵 Cachi

Cachi is a swift tool to parse and visualize test results contained in Xcode's .xcresult files on a web interface. It additionally offers a set of APIs that can be queried to extract information in json format from previously parsed test results.

<img src="Documentation/main_screenshot.png" width="840">


# Installation

```
brew install Subito-it/made/cachi
```

Or you can build manually using swift build.


# Usage

Cachi can be launched by passing the port for the web interface and the location where it should search for the .xcresult bundles.

You can optionally pass:
- `--search_depth` to specify how deep Cachi should traverse the location path. Default is 2, larger values may impact parsing speed. 
- `--merge` to merge multiple xcresults in the same folder as if they belong to the same test run. This can be used in advanced scenarios like for example test sharding on on multiple machines.
- `--ignore_system_failures` ignore system failures, which are generally tests that fail before launch

```bash
$ cachi --port number [--search_depth level] [--merge] path
```

## Endpoint documentation

http://local.host:port/v1/help will return a list of available endpoint with a short overview.

# Test result customization

The following keys can be added to the Info.plist in the .xcresult bundle which will be used when showing results:

- `branchName`
- `commitHash`
- `commitMessage`


# Contributions

Contributions are welcome! If you have a bug to report, feel free to help out by opening a new issue or sending a pull request.


## Authors

[Tomas Camin](https://github.com/tcamin) ([@tomascamin](https://twitter.com/tomascamin))


## License

Cachi is available under the Apache License, Version 2.0. See the LICENSE file for more info.
