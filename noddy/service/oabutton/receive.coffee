


API.service.oab.receive = (rid,files,url,title,description,firstname,lastname,cron,admin) ->
  r = oab_request.find {receiver:rid}
  if not r
    return 404
  else if r.received and not admin
    return 400
  else
    today = new Date().getTime()
    r.received = {date:today,from:r.email,description:description,validated:false}
    r.received.admin = admin
    r.received.cron = cron
    up = {}
    if url?
      r.received.url = url
    else
      description ?= "Deposited from Open Access Button"
      if files? and files.length > 0
        up.content = files[0].data
        up.name = files[0].filename
      up.publish = API.settings.service.openaccessbutton?.zenodo?.publish
      creators = [{name:''}]
      creators[0].name = lastname if lastname
      creators[0].name += ', ' + firstname if firstname
      if not firstname and not lastname and r.author
        try
          author
          for a in r.author
            if a.family and ( not author? or r.email.toLowerCase().indexOf(a.family.toLowerCase()) isnt -1 )
              author = a.family
              author += ', ' + a.given if a.given
          creators[0].name ?= author
      # http://developers.zenodo.org/#representation
      # journal_volume and journal_issue are acceptable too but we don't routinely collect those
      # access_right can be open embargoed restricted closed
      # if embargoed can also provide embargo_date
      # can provide access_conditions which is a string sentence explaining what conditions we will allow access for
      # license can be a string specifying the license type for open or embargoed content, using opendefinition license tags like cc-by
      # publication_date can be YYYY-MM-DD but we only keep year, so not much use
      meta =
        title:title,
        description:description,
        creators:creators,
        doi:r.doi,
        keywords:r.keywords,
        journal_title:r.journal,
        prereserve_doi:API.settings.service.openaccessbutton?.zenodo?.prereserve_doi and not r.doi?
      z = API.use.zenodo.deposition.create meta, up, API.settings.service.openaccessbutton?.zenodo?.token
      r.received.zenodo = 'https://zenodo.org/record/' + z.id if z.id
      r.received.zenodo_doi = z.metadata.prereserve_doi.doi if z.metadata?.prereserve_doi?.doi?
        
    oab_request.update r._id, {hold:'$DELETE',received:r.received,status:(if up.publish is false then 'moderate' else 'received')}
    API.mail.send
      service: 'openaccessbutton'
      from: 'requests@openaccessbutton.org'
      to: API.settings.service.openaccessbutton.notify.receive
      subject: 'Request ' + r._id + ' received' + (if up.publish is false then ' - zenodo publish required' else '')
      text: (if API.settings.dev then 'https://dev.openaccessbutton.org/request/' else 'https://openaccessbutton.org/request/') + r._id
    return {data: r}

