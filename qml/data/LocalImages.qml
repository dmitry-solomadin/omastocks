import QtQuick
import ".."

// Pictures from the web, as files bin/remote_images.py has downloaded and checked in
// its own process. Qt would buffer a remote image's whole response inside the shell,
// so Image and Canvas only ever get what local() returns.
DataRequest {
    id: root
    property var urls: []
    script: "../../bin/remote_images.py"
    arguments: urls
    function local(url) {
        const file = (root.data.images || {})[url]
        return /^file:\/\/\//.test(file) ? file : ""
    }
}
