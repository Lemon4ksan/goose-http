// A program that imports http.tls declares goose-tls in its root file.
// error: http needs the package tls
import http from "../../";
import http.tls;

fn main() {}
