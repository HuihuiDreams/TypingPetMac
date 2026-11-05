from django.db import transaction
from authentik.core.models import Application, User
from authentik.providers.proxy.models import ProxyProvider
from authentik.outposts.models import Outpost
from authentik.policies.models import PolicyBinding

slug = 'typing-pet-admin'
host = 'https://typing-pet-admin.miel.ing'
admin = User.objects.get(username='akadmin', is_active=True)
with transaction.atomic():
    existing = Application.objects.filter(slug=slug).first()
    if existing:
        assert existing.provider.external_host == host and existing.provider.mode == 'forward_single'
        bindings = list(PolicyBinding.objects.filter(target=existing, enabled=True))
        assert len(bindings) == 1 and bindings[0].user_id == admin.pk
        app = existing
    else:
        assert not ProxyProvider.objects.filter(external_host=host).exists()
        template = ProxyProvider.objects.get(pk=Application.objects.get(slug='sudo').provider_id)
        provider = ProxyProvider(name='Typing Pet Admin Forward Auth', mode='forward_single', external_host=host,
                                 authentication_flow=template.authentication_flow, authorization_flow=template.authorization_flow,
                                 invalidation_flow=template.invalidation_flow, grant_types=['authorization_code'])
        uri_type = type(template.redirect_uris[0])
        provider.redirect_uris = [uri_type(matching_mode=uri.matching_mode, url=uri.url.replace('sudo.miel.ing','typing-pet-admin.miel.ing'), redirect_uri_type=uri.redirect_uri_type) for uri in template.redirect_uris]
        provider.full_clean(exclude=['authentication_flow','backchannel_application','encryption_key','signing_key'])
        provider.save(); provider.set_oauth_defaults(); provider.save()
        app = Application(name='Typing Pet 팩 관리', slug=slug, provider=provider, meta_launch_url=host+'/', policy_engine_mode='any')
        app.full_clean(); app.save()
        binding = PolicyBinding(target=app, user=admin, enabled=True, order=0)
        binding.full_clean(exclude=['expires']); binding.save()
    Outpost.objects.get(name='authentik Embedded Outpost').providers.add(app.provider)
print('Typing Pet admin provider ready: forward_single, akadmin only')
