//
// ConTeXtSync
//       Tasks

var fs = require('fs')
var path = require('path')
var gulp = require('gulp')
var plugins = require('gulp-load-plugins')()
var yaml = require('js-yaml')
var del = require('del')

var config = yaml.safeLoad(fs.readFileSync('./config.yaml', 'utf-8'))

gulp.task('clean', function () {
  return del([
    path.join(config.download_path, '*'),
  ])
})


function retrieve(version) {
  return plugins.download(version.source)
    .pipe(plugins.unzip())
    .pipe(gulp.dest(config.download_path))
}

Object.keys(config.versions).forEach(function (name) {
  var version = config.versions[name]
  gulp.task('retrieve-' + name, ['clean'], function () {
    return retrieve(version)
  })
})


gulp.task('default', plugins.menu(gulp))
