# 🌵 Cachi

Cachi is a swift tool to parse and visualize test results contained in Xcode's .xcresult files on a web interface. It additionally offers a set of APIs that can be queried to extract information in json format from previously parsed test results.

Automatic screen recording (Xcode 15) and screenshot based xcresults are supported.

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
- `--attachment-viewer extension:/path/to/viewer.js` to register a JavaScript bundle that renders attachments with a matching file extension. Repeat the flag for multiple mappings (extensions are case-insensitive and should be provided without the leading dot).

```bash
$ cachi --port number [--search_depth level] [--merge] path
```

## Endpoint documentation

http://local.host:port/v1/help will return a list of available endpoint with a short overview.

# Test result customization

## Custom attachment viewers

Use the repeatable `--attachment-viewer` option to associate one or more attachment file extensions with a JavaScript bundle. When a table entry links to an attachment whose filename ends with a registered extension, Cachi serves an auto-generated `index.html` wrapper instead of the raw file. The wrapper embeds your script and exposes the selected attachment so that custom visualizations can be rendered.

- Scripts are proxied through the server at `/attachment-viewer/script`, so the JavaScript file can live anywhere accessible to the Cachi process.
- The generated page mirrors the following structure:

  ```html
  <!doctype html>
  <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Cachi Attachment Viewer - Example</title>
    </head>
    <body>
      <noscript>This app requires JavaScript.</noscript>
      <script>
        (function () {
          var s = document.createElement('script');
          s.src = '/attachment-viewer/script?viewer=json&attachment_filename=data.json';
          s.attachmentPath = 'resultId/attachmentHash';
          s.onload = function(){};
          document.body.appendChild(s);
        })();
      </script>
    </body>
  </html>
  ```

- The relative file path (from `/tmp/Cachi`) is made available to your script as a property on the script element:

```js
const attachmentPath = document.currentScript.attachmentPath;
```

**Note**: The `attachmentPath` is now a relative path from `/tmp/Cachi`. To construct the full path to the attachment file, append the `attachmentPath` to `/tmp/Cachi/`. For example, if `attachmentPath` is `resultId/attachmentHash`, the full path would be `/tmp/Cachi/resultId/attachmentHash`.

Remember to provide the extension without a dot (`json`, `html`, `csv`, …). Cachi normalizes extensions in a case-insensitive manner and rejects duplicate registrations to surface configuration mistakes early.

The following keys can be added to the Info.plist in the .xcresult bundle which will be used when showing results:

- `branchName`
- `commitHash`
- `commitMessage`
- `githubBaseUrl`: used to generate links to specific code lines within GitHub repositories. This allows to easily navigate to specific code segments associated to test failures. Example: https://github.com/Subito-it/Cachi
- `sourceBasePath`: used to cleanup file paths removing compilation base paths from source code locations. Example: /Users/someuser/path/to/repository will convert locations such as /Users/someuser/path/to/repository/modules/Somefile.swift into /modules/Somefile.swift.
- `xcresultPathToFailedTestName`: This parameter helps to clean up **System Failures** that occur when UI tests fail early in the execution process which results in test name not being included in the .xcresult bundle. Provide a dictionary where the key represents the `.xcresult` file paths, relative to the `sourceBasePath` and the value corresponds to the failed test name in the format `testSuiteName/testName`. Note: this can be used only when having a single `.xcresult` file generated per test. 

# Contributions

Contributions are welcome! If you have a bug to report, feel free to help out by opening a new issue or sending a pull request.


## Authors

[Tomas Camin](https://github.com/tcamin) ([@tomascamin](https://twitter.com/tomascamin))


## License

Cachi is available under the Apache License, Version 2.0. See the LICENSE file for more info.
