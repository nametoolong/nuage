Blueprinter.configure do |config|
  config.datetime_format = -> (datetime) {  datetime&.iso8601 }
  config.generator = Oj
end
