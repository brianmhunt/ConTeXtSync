//
// ConTeXtSync
//       Tasks

var fs = require('fs')
var path = require('path')
var gulp = require('gulp')
var plugins = require('gulp-load-plugins')()
var yaml = require('js-yaml')
var request = require('request')
var progress = require('request-progress')
var zlib = require('zlib')
var del = require('del')

var config = yaml.safeLoad(fs.readFileSync('./config.yaml', 'utf-8'))

gulp.task('clean', function () {
  return del([
    path.join(config.download_path, '*'),
  ])
})


function retrieve(version, done) {
  function on_decompress(err, res) {

  }


  function handler(err, res, body) {
    var new_etag = res.headers.etag;
    if (res.statusCode === 304) {
      process.stdout.write(" Done (no changes).\n")
    } else {
      process.stdout.write(" Done (etag: " + new_etag + ").\n")
      // Unzip.
      fs.writeFileSync(config.etag_path, new_etag)
      // zlib.unzip(body, on_decompress)
      // var zip = new Zip(config.download_path)
      // zip.extract({path: config.download_path})
    }
    done()
  }

  function on_read_file(err, etag) {
    etag = etag || "";
    var opts = {
      url: version.source,
      headers: {
        "If-None-Match": etag
      }
    }
    process.stdout.write("Downloading " + version.source + " [etag:" + (etag || "None")  + "]")
    progress(request(opts, handler), config.progress_settings)
      .on('progress', function(state) {
        process.stdout.write(" " + state.percent + "%")
      })
  }
  fs.readFile(config.etag_path, {encoding: 'utf8'}, on_read_file)
}

Object.keys(config.versions).forEach(function (name) {
  var version = config.versions[name]
  gulp.task('retrieve-' + name, ['clean'], function (done) {
    retrieve(version, done)
  })
})


gulp.task('default', plugins.menu(gulp))
