

@oab_dnr = new API.collection {index:"oab",type:"oab_dnr"}

API.service.oab.job_started = (job) ->
  tmpl = API.mail.template 'bulk_start.html'
  eml = job.email ? API.accounts.retrieve(job.user)?.emails[0].address
  if tmpl
    sub = API.service.oab.substitute tmpl.content, {_id: job._id, useremail: eml, jobname: job.name ? job._id}
    API.mail.send
      service: 'openaccessbutton'
      html: sub.content
      subject: sub.subject
      from: sub.from ? API.settings.service.openaccessbutton.mail.from
      to: eml
  else
    API.mail.send
      service: 'openaccessbutton'
      from: 'help@openaccessbutton.org'
      to: eml
      subject: 'Sheet upload confirmation'
      text: 'Thanks! \n\nYour sheet has been uploaded to Open Access Button. You will hear from us again once processing is complete.\n\nThe Open Access Button Team'

API.service.oab.job_complete = (job) ->
  if not job.email and job.user
    usr = API.accounts.retrieve job.user
    job.email = usr.emails[0].address
  tmpl = API.mail.template 'bulk_complete.html'
  sub = API.service.oab.substitute tmpl.content, {_id: job._id, useremail: job.email, jobname: job.name ? job._id}
  API.mail.send
    service: 'openaccessbutton'
    html: sub.content
    subject: sub.subject
    from: sub.from ? API.settings.service.openaccessbutton.mail.from
    to: job.email


API.service.oab.dnr = (email,add,refuse) ->
  return oab_dnr.search('*')?.hits?.hits if not email? and not add?
  ondnr = oab_dnr.find {email:email}
  if add and not ondnr
    oab_dnr.insert {email:email}
    # also set any requests where this author is the email address to refused - can't use the address!
    if refuse
      oab_request.each {email:email}, (req) -> API.service.oab.refuse req._id, 'Author DNRd their email address'
    else
      oab_request.each {email:email}, (req) ->
        if req.status in ['help','moderate','progress']
          oab_request.update r._id, {email:'',status:'help'}
  return ondnr? or add is true

API.service.oab.template = (template,refresh) ->
  if refresh or mail_template.count(undefined,{service:'openaccessbutton'}) is 0
    mail_template.remove {service:'openaccessbutton'}
    ghurl = API.settings.service.openaccessbutton?.templates_url
    m = API.tdm.extract
      url:ghurl
      matchers:['/href="/OAButton/website/blob/develop/emails/(.*?[.].*?)">/gi']
      start:'<table class="files'
      end:'</table'
    fls = []
    fls.push(fm.result[1]) for fm in m.matches
    flurl = ghurl.replace('github.com','raw.githubusercontent.com').replace('/tree','')
    for f in fls
      if f isnt 'archive'
        content = HTTP.call('GET',flurl + '/' + f).content
        API.mail.template undefined,{filename:f,service:'openaccessbutton',content:content}
    return API.mail.template {service:'openaccessbutton'}
  else if template
    return API.mail.template template
  else
    return API.mail.template {service:'openaccessbutton'}

API.service.oab.vars = (vars) ->
  if vars?.user
    u = API.accounts.retrieve vars.user.id
    if u
      vars.profession = u.service?.openaccessbutton?.profile?.profession ? 'person'
      vars.profession = 'person' if vars.profession.toLowerCase() is 'other'
      vars.affiliation = u.service?.openaccessbutton?.profile?.affiliation ? ''
    vars.userid = vars.user.id
    vars.fullname = u?.profile?.name ? ''
    if not vars.fullname and u?.profile?.firstname
      vars.fullname = u.profile.firstname
      vars.fullname += ' ' + u.profile.lastname if u.profile.lastname
    vars.username = vars.user.username ? vars.fullname
    vars.useremail = vars.user.email
  vars.profession ?= 'person'
  vars.fullname ?= 'a user'
  vars.name ?= 'colleague'
  return vars

API.service.oab.substitute = (content,vars,markdown) ->
  vars = API.service.oab.vars vars
  if API.settings.dev
    content = content.replace(/https:\/\/openaccessbutton.org/g,'https://dev.openaccessbutton.org')
    content = content.replace(/https:\/\/api.openaccessbutton.org/g,'https://dev.api.cottagelabs.com/service/oab')
  return API.mail.substitute content, vars, markdown

API.service.oab.mail = (opts={}) ->
  opts.service = 'openaccessbutton'
  opts.subject ?= 'Hello from Open Access Button'
  opts.from ?= API.settings.service.openaccessbutton?.requests_from

  if opts.bcc is 'ALL'
    opts.bcc = []
    Users.each {"roles.openaccessbutton":"*"}, (user) -> opts.bcc.push user.emails[0].address

  return API.mail.send opts
