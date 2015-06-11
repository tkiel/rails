Using Rails for API-only Apps
=============================

In this guide you will learn:

-   What Rails provides for API-only applications
-   How to configure Rails to start without any browser features
-   How to decide which middlewares you will want to include
-   How to decide which modules to use in your controller

endprologue.

### What is an API app?

Traditionally, when people said that they used Rails as an “API”, they
meant providing a programmatically accessible API alongside their web
application.\
For example, GitHub provides [an API](http://developer.github.com) that
you can use from your own custom clients.

With the advent of client-side frameworks, more developers are using
Rails to build a backend that is shared between their web application
and other native applications.

For example, Twitter uses its [public API](https://dev.twitter.com) in
its web application, which is built as a static site that consumes JSON
resources.

Instead of using Rails to generate dynamic HTML that will communicate
with the server through forms and links, many developers are treating
their web application as just another client, delivered as static HTML,
CSS and JavaScript, and consuming a simple JSON API

This guide covers building a Rails application that serves JSON
resources to an API client **or** client-side framework.

### Why use Rails for JSON APIs?

The first question a lot of people have when thinking about building a
JSON API using Rails is: “isn’t using Rails to spit out some JSON
overkill? Shouldn’t I just use something like Sinatra?”

For very simple APIs, this may be true. However, even in very HTML-heavy
applications, most of an application’s logic is actually outside of the
view layer.

The reason most people use Rails is that it provides a set of defaults
that allows us to get up and running quickly without having to make a
lot of trivial decisions.

Let’s take a look at some of the things that Rails provides out of the
box that are still applicable to API applications.

Handled at the middleware layer:

-   Reloading: Rails applications support transparent reloading. This
    works even if your application gets big and restarting the server
    for every request becomes non-viable.
-   Development Mode: Rails application come with smart defaults for
    development, making development pleasant without compromising
    production-time performance.
-   Test Mode: Ditto test mode.
-   Logging: Rails applications log every request, with a level of
    verbosity appropriate for the current mode. Rails logs in
    development include information about the request environment,
    database queries, and basic performance information.
-   Security: Rails detects and thwarts [IP spoofing
    attacks](http://en.wikipedia.org/wiki/IP_address_spoofing) and
    handles cryptographic signatures in a [timing
    attack](http://en.wikipedia.org/wiki/Timing_attack) aware way. Don’t
    know what an IP spoofing attack or a timing attack is? Exactly.
-   Parameter Parsing: Want to specify your parameters as JSON instead
    of as a URL-encoded String? No problem. Rails will decode the JSON
    for you and make it available in *params*. Want to use nested
    URL-encoded params? That works too.
-   Conditional GETs: Rails handles conditional *GET*, (*ETag* and
    *Last-Modified*), processing request headers and returning the
    correct response headers and status code. All you need to do is use
    the
    [stale?](http://api.rubyonrails.org/classes/ActionController/ConditionalGet.html#method-i-stale-3F)
    check in your controller, and Rails will handle all of the HTTP
    details for you.
-   Caching: If you use *dirty?* with public cache control, Rails will
    automatically cache your responses. You can easily configure the
    cache store.
-   HEAD requests: Rails will transparently convert *HEAD* requests into
    *GET* requests, and return just the headers on the way out. This
    makes *HEAD* work reliably in all Rails APIs.

While you could obviously build these up in terms of existing Rack
middlewares, I think this list demonstrates that the default Rails
middleware stack provides a lot of value, even if you’re “just
generating JSON”.

Handled at the ActionPack layer:

-   Resourceful Routing: If you’re building a RESTful JSON API, you want
    to be using the Rails router. Clean and conventional mapping from
    HTTP to controllers means not having to spend time thinking about
    how to model your API in terms of HTTP.
-   URL Generation: The flip side of routing is URL generation. A good
    API based on HTTP includes URLs (see [the GitHub gist
    API](http://developer.github.com/v3/gists/) for an example).
-   Header and Redirection Responses: *head :no\_content* and
    *redirect\_to user\_url(current\_user)* come in handy. Sure, you
    could manually add the response headers, but why?
-   Caching: Rails provides page, action and fragment caching. Fragment
    caching is especially helpful when building up a nested JSON object.
-   Basic, Digest and Token Authentication: Rails comes with
    out-of-the-box support for three kinds of HTTP authentication.
-   Instrumentation: Rails 3.0 added an instrumentation API that will
    trigger registered handlers for a variety of events, such as action
    processing, sending a file or data, redirection, and database
    queries. The payload of each event comes with relevant information
    (for the action processing event, the payload includes the
    controller, action, params, request format, request method and the
    request’s full path).
-   Generators: This may be passé for advanced Rails users, but it can
    be nice to generate a resource and get your model, controller, test
    stubs, and routes created for you in a single command.
-   Plugins: Many third-party libraries come with support for Rails that
    reduces or eliminates the cost of setting up and gluing together the
    library and the web framework. This includes things like overriding
    default generators, adding rake tasks, and honoring Rails choices
    (like the logger and cache backend).

Of course, the Rails boot process also glues together all registered
components. For example, the Rails boot process is what uses your
*config/database.yml* file when configuring ActiveRecord.

**The short version is**: you may not have thought about which parts of
Rails are still applicable even if you remove the view layer, but the
answer turns out to be “most of it”.

### The Basic Configuration

If you’re building a Rails application that will be an API server first
and foremost, you can start with a more limited subset of Rails and add
in features as needed.

You can generate a new api Rails app:

<shell>\
\$ rails new my\_api —api\
</shell>

This will do three main things for you:

-   Configure your application to start with a more limited set of
    middleware than normal. Specifically, it will not include any
    middleware primarily useful for browser applications (like cookie
    support) by default.
-   Make *ApplicationController* inherit from *ActionController::API*
    instead of *ActionController::Base*. As with middleware, this will
    leave out any *ActionController* modules that provide functionality
    primarily used by browser applications.
-   Configure the generators to skip generating views, helpers and
    assets when you generate a new resource.

If you want to take an existing app and make it an API app, follow the
following steps.

In *config/application.rb* add the following line at the top of the
*Application* class:

<ruby>\
config.api\_only!\
</ruby>

Change *app/controllers/application\_controller.rb*:

<ruby>

1.  instead of\
    class ApplicationController \< ActionController::Base\
    end

<!-- -->

1.  do\
    class ApplicationController \< ActionController::API\
    end\
    </ruby>

### Choosing Middlewares

An API application comes with the following middlewares by default.

-   *Rack::Cache*: Caches responses with public *Cache-Control* headers
    using HTTP caching semantics. See below for more information.
-   *Rack::Sendfile*: Uses a front-end server’s file serving support
    from your Rails application.
-   *Rack::Lock*: If your application is not marked as threadsafe
    (*config.threadsafe!*), this middleware will add a mutex around your
    requests.
-   *ActionDispatch::RequestId*:
-   *Rails::Rack::Logger*:
-   *Rack::Runtime*: Adds a header to the response listing the total
    runtime of the request.
-   *ActionDispatch::ShowExceptions*: Rescue exceptions and re-dispatch
    them to an exception handling application
-   *ActionDispatch::DebugExceptions*: Log exceptions
-   *ActionDispatch::RemoteIp*: Protect against IP spoofing attacks
-   *ActionDispatch::Reloader*: In development mode, support code
    reloading.
-   *ActionDispatch::ParamsParser*: Parse XML, YAML and JSON parameters
    when the request’s *Content-Type* is one of those.
-   *ActionDispatch::Head*: Dispatch *HEAD* requests as *GET* requests,
    and return only the status code and headers.
-   *Rack::ConditionalGet*: Supports the *stale?* feature in Rails
    controllers.
-   *Rack::ETag*: Automatically set an *ETag* on all string responses.
    This means that if the same response is returned from a controller
    for the same URL, the server will return a *304 Not Modified*, even
    if no additional caching steps are taken. This is primarily a
    client-side optimization; it reduces bandwidth costs but not server
    processing time.

Other plugins, including *ActiveRecord*, may add additional middlewares.
In general, these middlewares are agnostic to the type of app you are
building, and make sense in an API-only Rails application.

You can get a list of all middlewares in your application via:

<shell>\
\$ rake middleware\
</shell>

#### Using Rack::Cache

When used with Rails, *Rack::Cache* uses the Rails cache store for its
entity and meta stores. This means that if you use memcache, for your
Rails app, for instance, the built-in HTTP cache will use memcache.

To make use of *Rack::Cache*, you will want to use *stale?* in your
controller. Here’s an example of *stale?* in use.

<ruby>\
def show\
 @post = Post.find(params[:id])

if stale?(:last\_modified =\> `post.updated_at)
    render json: `post\
 end\
end\
</ruby>

The call to *stale?* will compare the *If-Modified-Since* header in the
request with *@post.updated\_at*. If the header is newer than the last
modified, this action will return a *304 Not Modified* response.
Otherwise, it will render the response and include a *Last-Modified*
header with the response.

Normally, this mechanism is used on a per-client basis. *Rack::Cache*
allows us to share this caching mechanism across clients. We can enable
cross-client caching in the call to *stale?*

<ruby>\
def show\
 @post = Post.find(params[:id])

if stale?(:last\_modified =\> `post.updated_at, :public => true)
    render json: `post\
 end\
end\
</ruby>

This means that *Rack::Cache* will store off *Last-Modified* value for a
URL in the Rails cache, and add an *If-Modified-Since* header to any
subsequent inbound requests for the same URL.

Think of it as page caching using HTTP semantics.

NOTE: The *Rack::Cache* middleware is always outside of the *Rack::Lock*
mutex, even in single-threaded apps.

#### Using Rack::Sendfile

When you use the *send\_file* method in a Rails controller, it sets the
*X-Sendfile* header. *Rack::Sendfile* is responsible for actually
sending the file.

If your front-end server supports accelerated file sending,
*Rack::Sendfile* will offload the actual file sending work to the
front-end server.

You can configure the name of the header that your front-end server uses
for this purposes using *config.action\_dispatch.x\_sendfile\_header* in
the appropriate environment config file.

You can learn more about how to use *Rack::Sendfile* with popular
front-ends in [the Rack::Sendfile
documentation](http://rubydoc.info/github/rack/rack/master/Rack/Sendfile)

The values for popular servers once they are configured to support
accelerated file sending:

<ruby>

1.  Apache and lighttpd\
    config.action\_dispatch.x\_sendfile\_header = “X-Sendfile”

<!-- -->

1.  nginx\
    config.action\_dispatch.x\_sendfile\_header = “X-Accel-Redirect”\
    </ruby>

Make sure to configure your server to support these options following
the instructions in the *Rack::Sendfile* documentation.

NOTE: The *Rack::Sendfile* middleware is always outside of the
*Rack::Lock* mutex, even in single-threaded apps.

#### Using ActionDispatch::ParamsParser

*ActionDispatch::ParamsParser* will take parameters from the client in
JSON and make them available in your controller as *params*.

To use this, your client will need to make a request with JSON-encoded
parameters and specify the *Content-Type* as *application/json*.

Here’s an example in jQuery:

<plain>\
jQuery.ajax({\
 type: ‘POST’,\
 url: ‘/people’\
 dataType: ‘json’,\
 contentType: ‘application/json’,\
 data: JSON.stringify({ person: { firstName: “Yehuda”, lastName: “Katz”
} }),

success: function(json) { }\
});\
</plain>

*ActionDispatch::ParamsParser* will see the *Content-Type* and your
params will be *{ :person =\> { :firstName =\> “Yehuda”, :lastName =\>
“Katz” } }*.

#### Other Middlewares

Rails ships with a number of other middlewares that you might want to
use in an API app, especially if one of your API clients is the browser:

-   *Rack::MethodOverride*: Allows the use of the *\_method* hack to
    route POST requests to other verbs.
-   *ActionDispatch::Cookies*: Supports the *cookie* method in
    *ActionController*, including support for signed and encrypted
    cookies.
-   *ActionDispatch::Flash*: Supports the *flash* mechanism in
    *ActionController*.
-   *ActionDispatch::BestStandards*: Tells Internet Explorer to use the
    most standards-compliant available renderer. In production mode, if
    ChromeFrame is available, use ChromeFrame.
-   Session Management: If a *config.session\_store* is supplied, this
    middleware makes the session available as the *session* method in
    *ActionController*.

Any of these middlewares can be adding via:

<ruby>\
config.middleware.use Rack::MethodOverride\
</ruby>

#### Removing Middlewares

If you don’t want to use a middleware that is included by default in the
API-only middleware set, you can remove it using
*config.middleware.delete*:

<ruby>\
config.middleware.delete ::Rack::Sendfile\
</ruby>

Keep in mind that removing these features may remove support for certain
features in *ActionController*.

### Choosing Controller Modules

An API application (using *ActionController::API*) comes with the
following controller modules by default:

-   *ActionController::UrlFor*: Makes *url\_for* and friends available
-   *ActionController::Redirecting*: Support for *redirect\_to*
-   *ActionController::Rendering*: Basic support for rendering
-   *ActionController::Renderers::All*: Support for *render :json* and
    friends
-   *ActionController::ConditionalGet*: Support for *stale?*
-   *ActionController::ForceSSL*: Support for *force\_ssl*
-   *ActionController::RackDelegation*: Support for the *request* and
    *response* methods returning *ActionDispatch::Request* and
    *ActionDispatch::Response* objects.
-   *ActionController::DataStreaming*: Support for *send\_file* and
    *send\_data*
-   *AbstractController::Callbacks*: Support for *before\_filter* and
    friends
-   *ActionController::Instrumentation*: Support for the instrumentation
    hooks defined by *ActionController* (see [the
    source](https://github.com/rails/rails/blob/master/actionpack/lib/action_controller/metal/instrumentation.rb)
    for more).
-   *ActionController::Rescue*: Support for *rescue\_from*.

Other plugins may add additional modules. You can get a list of all
modules included into *ActionController::API* in the rails console:

<shell>\
\$ irb\
\>\> ActionController::API.ancestors -
ActionController::Metal.ancestors\
</shell>

#### Adding Other Modules

All ActionController modules know about their dependent modules, so you
can feel free to include any modules into your controllers, and all
dependencies will be included and set up as well.

Some common modules you might want to add:

-   *AbstractController::Translation*: Support for the *l* and *t*
    localization and translation methods. These delegate to
    *I18n.translate* and *I18n.localize*.
-   *ActionController::HTTPAuthentication::Basic* (or *Digest*
    or +Token): Support for basic, digest or token HTTP authentication.
-   *AbstractController::Layouts*: Support for layouts when rendering.
-   *ActionController::MimeResponds*: Support for content negotiation
    (*respond\_to*, *respond\_with*).
-   *ActionController::Cookies*: Support for *cookies*, which includes
    support for signed and encrypted cookies. This requires the cookie
    middleware.

The best place to add a module is in your *ApplicationController*. You
can also add modules to individual controllers.
