import type { ReactNode } from 'react';
import { Collapsible } from '@base-ui/react/collapsible';
import { ChevronDown } from 'lucide-react';

export default function Disclosure({ label, children, className }: { label: string; children: ReactNode; className?: string }) {
  return <Collapsible.Root className={className}>
    <Collapsible.Trigger className="disclosure-trigger">{label}<ChevronDown size={15} aria-hidden="true" /></Collapsible.Trigger>
    <Collapsible.Panel className="disclosure-panel"><div className="disclosure-content">{children}</div></Collapsible.Panel>
  </Collapsible.Root>;
}
